{
  inputs,
  rootPath,
  program,
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

  hyprConfigModules = luaModules "${rootPath}/configs/hypr/config";
  hyprlandAutoload = luaManifest "hyprland-autoload.lua" "config" hyprConfigModules;

  # the tagged source requests glaze 7 while its pinned nixpkgs provides glaze 8
  # relaxing the cmake constraint keeps the build offline and matches nixpkgs' fix
  hyprlandPackage =
    pkgs:
    inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland.overrideAttrs (old: {
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
          jq
          gawk
          procps
          coreutils
          hyprctlPkg
          pulseaudio
        ];
        text = builtins.readFile ../../../scripts/audio-opacity.sh;
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
  den.aspects.hyprland = program {
    hosts = [
      "khion"
      "lumi"
    ];
    pkg = pkgs: pkgs.pyprland;
    nixos =
      { pkgs, ... }:
      let
        hyprlandPkg = hyprlandPackage pkgs;
        # the gloview input follows this same tagged compositor and owns its package details
        gloviewPkg = inputs.gloview.packages.${pkgs.stdenv.hostPlatform.system}.gloview;
      in
      [
        {
          # xdg-desktop-portal 1.22 requires a target unmanaged hyprland sessions do not start
          # remove this overlay once the frontend supports these sessions upstream
          nixpkgs.overlays = [
            (_: prev: {
              xdg-desktop-portal = prev.xdg-desktop-portal.overrideAttrs (old: {
                postPatch = (old.postPatch or "") + ''
                  substituteInPlace src/xdg-desktop-portal.service.in \
                    --replace-fail \
                      "Requisite=graphical-session.target" \
                      "Requires=dbus.service"
                  sed -i '/^After=graphical-session.target$/i After=dbus.service' \
                    src/xdg-desktop-portal.service.in
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
          # expose gloview through the system profile so the lua startup can load a stable path
          environment.systemPackages = [ gloviewPkg ];
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

        }
      ];
    imports = [ audioOpacityService ];
    files = [
      {
        src = hyprlandAutoload;
        dest = ".config/hypr/autoload.lua";
      }
      {
        src = "${rootPath}/configs/pypr/config.toml";
        dest = ".config/pypr/config.toml";
      }
    ];
    # separate declarations keep nested config and library files visible to furnish
    directories = [
      {
        src = "${rootPath}/configs/hypr";
        dest = ".config/hypr";
        exclude = [
          ".luarc.json"
          "config"
          "lib"
        ];
      }
      {
        src = "${rootPath}/configs/hypr/config";
        dest = ".config/hypr/config";
      }
      {
        src = "${rootPath}/configs/hypr/lib";
        dest = ".config/hypr/lib";
      }
    ];
    theme = {
      id = "hyprland";
      output = ".config/hypr/colors.lua";
      reload = "hyprctl reload";
      renderers = {
        caelestia = {
          source = "${rootPath}/configs/hypr/caelestia-colors.lua";
          placedAs = "colors.lua";
        };
        illogical-impulse = {
          source = "${rootPath}/configs/hypr/colors.lua";
          sharedWith = [ "end4-pc" ];
        };
      };
    };
  };
}
