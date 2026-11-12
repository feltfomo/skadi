{
  lexicon,
  inputs,
  ...
}:
let
  herdrFor = pkgs: inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
{
  flake-file.inputs.herdr = {
    url = "github:herdrdev/herdr";
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
        toml = inputs.lexicon.lib.toml { inherit pkgs; };
        palette = import ./_themes.nix;
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
            template = toml.render palette;
            placedAs = "reactive.toml";
          }
          {
            subId = "pickr";
            output = ".config/herdr/plugins/config/javoscript.herdr-pickr/config.json";
            template = ./config/themes/pickr-reactive.json;
          }
        ];
      };
  };
}
