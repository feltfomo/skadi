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
        declared = toml.merge "noctalia-baseline.toml" {
          sources = (map (name: "${rootPath}/configs/noctalia/${name}") (builtins.attrNames configFiles)) ++ [
            (pluginSource pkgs)
          ];
          conflict = "last";
        };
        session = pkgs.writeShellApplication {
          name = "noctalia-session";
          text = ''
            exec ${python}/bin/python ${rootPath}/scripts/noctalia-session.py ${noctalia}/bin/noctalia ${declared} "$@"
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
      }
    ];
    furnish.files = { pkgs, ... }: [
      {
        destination = ".config/noctalia/plugin-sources.toml";
        source = pluginSource pkgs;
      }
    ];
  };
}
