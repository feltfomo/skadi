{
  inputs,
  lexicon,
  ...
}:
let
  lib = inputs.nixpkgs.lib;
  settings = import ./_settings.nix;
  plugins = {
    enabled = [
      "nightwatch75/claude-cockpit"
      "noctalia/mpvpaper"
    ];
    auto_update = "none";
    source = [
      {
        name = "nix-community";
        kind = "path";
        location = "${inputs.noctalia-community-plugins}";
        enabled = true;
      }
      {
        name = "nix-official";
        kind = "path";
        location = "${inputs.noctalia-official-plugins}";
        enabled = true;
      }
      {
        name = "community";
        kind = "git";
        location = "https://github.com/noctalia-dev/community-plugins";
        enabled = false;
      }
      {
        name = "official";
        kind = "git";
        location = "https://github.com/noctalia-dev/official-plugins";
        enabled = false;
      }
    ];
  };
  pluginSource =
    pkgs:
    (inputs.lexicon.lib.toml { inherit pkgs; }).generate "noctalia-plugin-sources.toml" {
      inherit plugins;
    };
  configSources =
    pkgs:
    lib.mapAttrs (
      name: value: (inputs.lexicon.lib.toml { inherit pkgs; }).generate name value
    ) settings.files;
  profiles = builtins.attrNames settings.profiles;
  profileSource =
    pkgs: profile:
    (inputs.lexicon.lib.toml { inherit pkgs; }).generate "${profile}.toml" settings.profiles.${profile};

in
{
  flake-file.inputs = {
    noctalia = {
      url = "github:noctalia-dev/noctalia";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    noctalia-community-plugins = {
      url = "github:noctalia-dev/community-plugins/e9dec7443b8a70ab606dc72669fb122a9d668bce";
      flake = false;
    };
    # path sources can't use a catalog's older release rows, so this stays on the last
    # commit whose mpvpaper plugin fits Noctalia 5.3.0's plugin API 34
    noctalia-official-plugins = {
      url = "github:noctalia-dev/official-plugins/8c6b90fa92519bd2da1dd8b5f2cc940cce08367f";
      flake = false;
    };
  };

  flake-file.nixConfig = {
    extra-substituters = [ "https://noctalia.cachix.org" ];
    extra-trusted-public-keys = [
      "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
    ];
  };

  den.aspects.noctalia = lexicon {
    package = pkgs: import ./_package.nix { inherit inputs pkgs; };
    nixos = [
      { value.services.gnome.gnome-keyring.enable = true; }
    ];
    homeManager =
      { pkgs, ... }:
      let
        python = pkgs.python3.withPackages (packages: [ packages.tomlkit ]);
        noctalia = import ./_package.nix { inherit inputs pkgs; };
        toml = inputs.lexicon.lib.toml { inherit pkgs; };
        declared =
          profile:
          toml.merge "noctalia-${profile}-baseline.toml" {
            sources = (builtins.attrValues (configSources pkgs)) ++ [
              (pluginSource pkgs)
              (profileSource pkgs profile)
            ];
            conflict = "last";
          };
        baselines = pkgs.linkFarm "noctalia-baselines" (
          map (profile: {
            name = "${profile}.toml";
            path = declared profile;
          }) profiles
        );
        session = pkgs.writeShellApplication {
          name = "noctalia-session";
          text = ''
            exec ${pkgs.systemd}/bin/systemd-cat --identifier=noctalia ${python}/bin/python ${./session.py} ${noctalia}/bin/noctalia ${baselines} "$@"
          '';
        };
        # the plugin stops a player with SIGTERM, which a paused mpvpaper can hang on, and the old
        # video keeps running under the new one. so each start clears older players on its output.
        mpvpaper = pkgs.symlinkJoin {
          name = "mpvpaper";
          paths = [
            (pkgs.writeShellApplication {
              name = "mpvpaper";
              text = ''
                if (($# >= 2)); then
                  output=''${*: -2:1}
                  while read -r pid; do
                    mapfile -d "" -t args <"/proc/$pid/cmdline" || continue
                    ((''${#args[@]} >= 2)) || continue
                    [[ ''${args[0]##*/} == mpvpaper ]] || continue
                    other=''${args[-2]}
                    if [[ $output == "*" || $other == "*" || $other == "$output" ]]; then
                      kill -KILL "$pid" 2>/dev/null || true
                    fi
                  done < <(${pkgs.procps}/bin/pgrep -f '(^|/)mpvpaper ' || true)
                fi
                exec ${pkgs.mpvpaper}/bin/mpvpaper "$@"
              '';
            })
            pkgs.mpvpaper
          ];
        };
      in
      {
        home.packages = with pkgs; [
          mpvpaper
          session
          satty
          socat
          mpv
        ];
      };

    furnish.files =
      { pkgs, ... }:
      lib.mapAttrsToList (name: source: {
        destination = ".config/noctalia/${name}";
        inherit source;
      }) (configSources pkgs)
      ++ map (profile: {
        destination = ".config/noctalia/profiles/${profile}/noctalia/config.toml";
        source = profileSource pkgs profile;
      }) profiles
      ++ [
        {
          destination = ".config/noctalia/plugin-sources.toml";
          source = pluginSource pkgs;
        }
      ];
  };
}
