{
  lexicon,
  inputs,
  ...
}:
let
  herdrFor = pkgs: inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.herdr;
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
        pickr = pkgs.callPackage ./_pickr.nix { inherit herdr; };
      in
      {
        home.activation.herdrPickr = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          run ${herdr}/bin/herdr plugin link ${pickr}
        '';
      };
    theme =
      { pkgs, ... }:
      let
        herdr = herdrFor pkgs;
        reload = pkgs.writeShellApplication {
          name = "herdr-reload-config";
          # each named session runs its own server; plain reload-config only reaches the default one.
          text = ''
            ${herdr}/bin/herdr session list --json \
              | ${pkgs.jq}/bin/jq -er '.sessions[] | select(.running) | [.default, .name] | @tsv' \
              | while IFS=$'\t' read -r default name; do
                  if [ "$default" = true ]; then
                    ${herdr}/bin/herdr server reload-config
                  else
                    ${herdr}/bin/herdr --session "$name" server reload-config
                  fi
                done
          '';
        };
      in
      {
        id = "herdr";
        templates = [
          {
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
                source = ./config/themes/reactive.toml;
                sharedWith = [
                  "illogical-impulse"
                  "serpantinum"
                  "end4-pc"
                  "dms"
                ];
              };
              caelestia.source = ./config/themes/caelestia.toml;
            };
          }
          {
            subId = "pickr";
            output = ".config/herdr/plugins/config/javoscript.herdr-pickr/config.json";
            renderers = {
              noctalia = {
                source = ./config/themes/pickr-reactive.json;
                sharedWith = [
                  "illogical-impulse"
                  "serpantinum"
                  "end4-pc"
                  "dms"
                ];
              };
              caelestia.source = ./config/themes/pickr-caelestia.json;
            };
          }
        ];
      };
  };
}
