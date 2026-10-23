{
  lexicon,
  inputs,
  ...
}:
let
  herdrFor =
    pkgs:
    inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.herdr.override {
      zig = pkgs.zig_0_16;
    };
in
{
  flake-file.inputs.llm-agents = {
    url = "github:numtide/llm-agents.nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  den.aspects.herdr = lexicon {
    package = herdrFor;
    homeManager =
      { pkgs, lib, ... }:
      let
        herdr = herdrFor pkgs;
        plugin = pkgs.callPackage ../../pkgs/herdr-nvim { };
        pickr = pkgs.callPackage ../../pkgs/herdr-pickr { inherit herdr; };
      in
      {
        home = {
          packages = [ plugin ];
          activation = {
            herdrNvim = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
              run ${herdr}/bin/herdr plugin link ${plugin}
            '';
            herdrPickr = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
              run ${herdr}/bin/herdr plugin link ${pickr}
            '';
          };
        };
      };
    theme =
      { pkgs, ... }:
      let
        herdr = herdrFor pkgs;
        reload = pkgs.writeShellApplication {
          name = "herdr-reload-config";
          text = ''
            status="$(${herdr}/bin/herdr status server --json | ${pkgs.jq}/bin/jq -er '.status')"
            case "$status" in
              running) exec ${herdr}/bin/herdr server reload-config ;;
              not_running) ;;
              *) printf 'Unexpected Herdr server status: %s\n' "$status" >&2; exit 1 ;;
            esac
          '';
        };
      in
      {
        id = "herdr";
        output = ".config/herdr/config.toml";
        reload = "${reload}/bin/herdr-reload-config";
        merge = {
          format = "toml";
          base = {
            onboarding = false;
            keys.command = [
              {
                key = "prefix+f";
                type = "plugin_action";
                command = "javoscript.herdr-pickr.panes-all";
                description = "find pane";
              }
              {
                key = "prefix+e";
                type = "plugin_action";
                command = "chmarax.herdr-nvim.toggle";
                description = "nvim sidebar";
              }
              {
                key = "prefix+o";
                type = "plugin_action";
                command = "chmarax.herdr-nvim.pick-file";
                description = "open file from agent output";
              }
            ];
            ui = {
              agent_panel_sort = "spaces";
              toast.delivery = "herdr";
            };
            theme = {
              name = "kanagawa-lotus";
              auto_switch = false;
            };
          };
        };
        renderers = {
          noctalia = {
            source = ../../configs/herdr/themes/reactive.toml;
            sharedWith = [
              "illogical-impulse"
              "serpantinum"
              "end4-pc"
              "dms"
            ];
          };
          caelestia.source = ../../configs/herdr/themes/caelestia.toml;
        };
      };
  };
}
