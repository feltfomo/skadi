{
  config,
  den,
  inputs,
  lexicon,
  ...
}:
let
  # config modules are discovered during evaluation while libraries stay explicit
  luaModules =
    directory:
    let
      entries = builtins.readDir directory;
    in
    builtins.filter (name: entries.${name} == "regular" && builtins.match ".*\\.lua$" name != null) (
      builtins.attrNames entries
    );
  # generated manifests avoid filesystem scanning inside hyprland's lua runtime
  luaManifest =
    name: prefix: modules:
    builtins.toFile name (
      builtins.concatStringsSep "\n" (
        map (
          file:
          let
            moduleName = builtins.substring 0 (builtins.stringLength file - 4) file;
          in
          ''require("${prefix}.${moduleName}")''
        ) modules
      )
      + "\n"
    );

  hyprConfigModules = luaModules ./config/config;
  hyprlandAutoload = luaManifest "hyprland-autoload.lua" "config" hyprConfigModules;

  # the tagged source requests glaze 7 while its pinned nixpkgs provides glaze 8
  # relaxing the cmake constraint keeps the build offline and matches nixpkgs' fix
  hyprlandPackage =
    pkgs:
    (inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland.override {
      makeWrapper = pkgs.makeBinaryWrapper;
    }).overrideAttrs
      (old: {
        postPatch = (old.postPatch or "") + ''
          substituteInPlace CMakeLists.txt --replace-fail "glaze 7...<8" "glaze"
        '';
      });

  # keep audio-playing windows opaque while inactive.
  audioOpacityService =
    { pkgs, ... }:
    with pkgs;
    let
      hyprctlPkg = hyprlandPackage pkgs;
      audio-opacity = writeShellApplication {
        name = "audio-opacity";
        runtimeInputs = [
          hyprctlPkg
          pulseaudio
          coreutils
          procps
          gawk
          jq
        ];
        text = builtins.readFile ./audio-opacity.sh;
      };
    in
    {
      systemd.user.services.audio-opacity = {
        Unit = {
          Description = "Undim windows that are playing audio while inactive";
          After = [ "graphical-session.target" ];
          PartOf = [ "graphical-session.target" ];
        };
        Service = {
          ExecStart = "${audio-opacity}/bin/audio-opacity";
          Restart = "always";
          RestartSec = 2;
        };
      };
    };
in
{
  flake-file = {
    inputs = {
      hyprland.url = "github:hyprwm/Hyprland?ref=v0.56.2";
    };
    nixConfig = {
      extra-substituters = [ "https://hyprland.cachix.org" ];
      extra-trusted-public-keys = [
        "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
      ];
    };
  };

  den.aspects.hyprland = {
    includes = with den.aspects; [
      gtk-theme
      noctalia
      wayland
      fuzzel
      kitty
    ];
  }
  // lexicon {
    package = pkgs: pkgs.pyprland;
    nixos =
      { pkgs, ... }:
      let
        hyprlandPkg = hyprlandPackage pkgs;
        hyprlandPkgs = inputs.hyprland.inputs.nixpkgs.legacyPackages.${pkgs.stdenv.hostPlatform.system};
      in
      [
        {
          value = {
            # native Hyprland exports its display without starting graphical-session.target.
            # gate portal activation on that export so lingering users cannot cache GTK-only backends before login.
            nixpkgs.overlays = [
              (_: prev: {
                xdg-desktop-portal = prev.xdg-desktop-portal.overrideAttrs (old: {
                  postPatch = (old.postPatch or "") + ''
                    substituteInPlace src/xdg-desktop-portal.service.in \
                      --replace-fail \
                        "Requisite=graphical-session.target" \
                        "ConditionEnvironment=WAYLAND_DISPLAY"
                  '';
                });
              })
            ];

            programs.hyprland = {
              enable = true;
              package = hyprlandPkg;
              portalPackage =
                inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland;
            };
            hardware.graphics = {
              package = hyprlandPkgs.mesa;
              package32 = hyprlandPkgs.pkgsi686Linux.mesa;
            };
            environment.systemPackages = [ pkgs.hyprland-preview-share-picker ];
            programs.ydotool.enable = true;
            services.flatpak.enable = true;

            xdg.portal = {
              extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
              config.hyprland = {
                default = [
                  "hyprland"
                  "gtk"
                ];
                "org.freedesktop.impl.portal.ScreenCast" = [ "hyprland" ];
                "org.freedesktop.impl.portal.Screenshot" = [ "hyprland" ];
                "org.freedesktop.impl.portal.FileChooser" = [ "gtk" ];
              };
            };

          };
        }
      ];
    homeManager = { pkgs, ... }: {
      imports = [ audioOpacityService ];
      home.packages = with pkgs; [
        hyprpicker
        grimblast
        hyprshot
      ];
    };
    furnish.files = { host, pkgs, ... }: [
      {
        destination = ".config/hyprland-preview-share-picker/config.yaml";
        source = (pkgs.formats.yaml { }).generate "hyprland-share-picker.yaml" {
          stylesheets = [ "style.css" ];
          default_page = "windows";
          window = {
            width = 1080;
            height = 640;
          };
          image = {
            resize_size = 480;
            widget_size = 160;
          };
          classes.window = "share-picker";
          windows = {
            min_per_row = 2;
            max_per_row = 3;
            spacing = 16;
            clicks = 2;
          };
          outputs = {
            show_label = true;
            spacing = 8;
            clicks = 2;
          };
          region.command = "${pkgs.lib.getExe pkgs.slurp} -f '%o@%X,%Y,%W,%H'";
        };
      }
      {
        destination = ".config/hyprland-preview-share-picker/style.css";
        source = ./share-picker/style.css;
      }
      {
        source =
          pkgs.writeText "hyprland-shared-binds.lua"
            (config.skadi.bindings {
              lib = inputs.nixpkgs.lib;
              hostName = host.name;
            }).hyprland;
        destination = ".config/hypr/shared-binds.lua";
      }
      {
        source = hyprlandAutoload;
        destination = ".config/hypr/autoload.lua";
      }
      {
        source = (inputs.lexicon.lib.toml { inherit pkgs; }).generate "pypr-config.toml" (
          import ./_pypr.nix
        );
        destination = ".config/pypr/config.toml";
      }
      {
        destination = ".config/hypr/xdph.conf";
        source = pkgs.writeText "hyprland-share-picker-portal.conf" ''
          screencopy {
            custom_picker_binary = ${pkgs.lib.getExe pkgs.hyprland-preview-share-picker}
          }
        '';
      }
    ];
    # separate declarations keep nested config and library files visible to furnish
    furnish.directories = [
      {
        source = ./config/config;
        destination = ".config/hypr/config";
      }
      {
        source = ./config/lib;
        destination = ".config/hypr/lib";
      }
      {
        source = ./config;
        destination = ".config/hypr";
        exclude = [
          ".luarc.json"
          "config"
          "lib"
        ];
      }
    ];
    theme = {
      id = "hyprland";
      output = ".config/hypr/colors.lua";
      reload = ''if [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ]; then hyprctl reload; fi'';
      template = ./config/colors.lua;
    };
  };
}
