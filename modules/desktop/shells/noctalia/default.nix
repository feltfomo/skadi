{
  inputs,
  lexicon,
  ...
}:
let
  lib = inputs.nixpkgs.lib;
  settings = import ./_settings.nix;
  plugins = {
    enabled = [ "miguelfm/ai-triage" ];
    auto_update = "none";
    source = [
      {
        name = "nix-community";
        kind = "path";
        location = "${inputs.noctalia-community-plugins}";
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
    ai-usagebar = {
      url = "github:akitaonrails/ai-usagebar";
      inputs.nixpkgs.follows = "nixpkgs";
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
      in
      {
        home.packages = [
          inputs.ai-usagebar.packages.${pkgs.stdenv.hostPlatform.system}.default
          pkgs.satty
          session
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
