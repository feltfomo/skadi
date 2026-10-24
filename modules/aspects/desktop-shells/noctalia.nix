{
  inputs,
  lexicon,
  rootPath,
  ...
}:
let
  lib = inputs.nixpkgs.lib;
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
  configFiles = lib.filterAttrs (name: kind: kind == "regular" && lib.hasSuffix ".toml" name) (
    builtins.readDir ../../../configs/noctalia
  );
  profiles = [
    "hyprland"
    "mangowm"
  ];
  profileSource = profile: "${rootPath}/configs/noctalia/profiles/${profile}.toml";

in
{
  flake-file.inputs = {
    noctalia-community-plugins = {
      url = "github:noctalia-dev/community-plugins/e9dec7443b8a70ab606dc72669fb122a9d668bce";
      flake = false;
    };
    ai-usagebar = {
      url = "github:akitaonrails/ai-usagebar";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  den.aspects.noctalia = lexicon {
    homeManager =
      { pkgs, ... }:
      let
        python = pkgs.python3.withPackages (packages: [ packages.tomlkit ]);
        noctalia = inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default;
        toml = inputs.lexicon.lib.toml { inherit pkgs; };
        declared =
          profile:
          toml.merge "noctalia-${profile}-baseline.toml" {
            sources = (map (name: "${rootPath}/configs/noctalia/${name}") (builtins.attrNames configFiles)) ++ [
              (pluginSource pkgs)
              (profileSource profile)
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
            exec ${python}/bin/python ${rootPath}/scripts/noctalia-session.py ${noctalia}/bin/noctalia ${baselines} "$@"
          '';
        };
      in
      {
        home.packages = [
          inputs.ai-usagebar.packages.${pkgs.stdenv.hostPlatform.system}.default
          session
        ];
      };

    furnish.directories = [
      {
        source = "${rootPath}/configs/noctalia";
        destination = ".config/noctalia";
        exclude = [ "profiles" ];
      }
    ];
    furnish.files =
      { pkgs, ... }:
      [
        {
          destination = ".config/noctalia/plugin-sources.toml";
          source = pluginSource pkgs;
        }
      ]
      ++ map (profile: {
        destination = ".config/noctalia/profiles/${profile}/noctalia/config.toml";
        source = profileSource profile;
      }) profiles;
  };
}
