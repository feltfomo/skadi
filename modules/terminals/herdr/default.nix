{
  config,
  lexicon,
  inputs,
  ...
}:
let
  herdrFor = pkgs: inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.herdr-scoped;
in
{
  flake-file.inputs.llm-agents = {
    url = "github:numtide/llm-agents.nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  flake-file.inputs.herdr-source = {
    url = "github:herdrdev/herdr/2ecf19a92fc3a7fff75b6ce3655ef04f4625ec01";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  perSystem =
    { system, ... }:
    {
      packages.herdr-scoped = inputs.herdr-source.packages.${system}.default.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [ ./client-state.patch ];
      });
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
        toml = inputs.lexicon.lib.toml { inherit pkgs; };
        themes = import ./_themes.nix;
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
                source = toString (toml.generate "herdr-reactive.toml" themes.reactive);
                placedAs = "reactive.toml";
                sharedWith = config.skadi.theme.noctaliaCompatibleRenderers;
              };
              caelestia = {
                source = toString (toml.generate "herdr-caelestia.toml" themes.caelestia);
                placedAs = "caelestia.toml";
              };
            };
          }
          {
            subId = "pickr";
            output = ".config/herdr/plugins/config/javoscript.herdr-pickr/config.json";
            renderers = {
              noctalia = {
                source = ./config/themes/pickr-reactive.json;
                sharedWith = config.skadi.theme.noctaliaCompatibleRenderers;
              };
              caelestia.source = ./config/themes/pickr-caelestia.json;
            };
          }
        ];
      };
  };
}
