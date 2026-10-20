{
  program,
  inputs,
  ...
}:
let
  themeTemplate =
    name:
    builtins.toFile "herdr-${name}.toml" (
      builtins.readFile ../../configs/herdr/config.toml
      + "\n"
      + builtins.readFile (../../configs/herdr/themes + "/${name}.toml")
    );
in
{
  flake-file.inputs.llm-agents = {
    url = "github:numtide/llm-agents.nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  # theme output includes the keybindings because herdr reads one config file.
  den.aspects.herdr = program {
    pkg = pkgs: inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.herdr;
    imports = [
      (
        { pkgs, lib, ... }:
        let
          herdr = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.herdr;
          plugin = pkgs.callPackage ../../pkgs/herdr-nvim { };
        in
        {
          home.packages = [ plugin ];
          home.activation.herdrNvim = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            run ${herdr}/bin/herdr plugin link ${plugin}
          '';
        }
      )
    ];
    theme = {
      id = "herdr";
      output = ".config/herdr/config.toml";
      reload = "herdr server reload-config";
      renderers = {
        noctalia = {
          source = themeTemplate "reactive";
          sharedWith = [
            "illogical-impulse"
            "serpantinum"
            "end4-pc"
            "dms"
          ];
        };
        caelestia.source = themeTemplate "caelestia";
      };
    };
  };
}
