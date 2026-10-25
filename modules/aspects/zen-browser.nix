{ lexicon, inputs, ... }:
{
  den.aspects.zen-browser = lexicon {
    package = pkgs: inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.twilight;
    homeManager =
      { pkgs, lib, ... }:
      let
        setup = import ../../lib/theme-setup.nix { inherit pkgs; };
      in
      {
        home.activation.zenBrowserTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          run ${setup}/bin/app-theme-setup zen-browser
        '';
      };
    theme =
      { pkgs, ... }:
      let
        setup = import ../../lib/theme-setup.nix { inherit pkgs; };
      in
      {
        id = "zen-browser";
        templates = [
          {
            subId = "chrome";
            output = ".config/zen/theme/userChrome.css";
            reload = "${setup}/bin/app-theme-setup zen-browser";
            renderers = {
              noctalia = {
                source = ../../configs/zen-browser/reactive-chrome.css;
                sharedWith = [
                  "illogical-impulse"
                  "serpantinum"
                  "end4-pc"
                  "dms"
                ];
              };
              caelestia.source = ../../configs/zen-browser/caelestia-chrome.css;
            };
          }
          {
            subId = "content";
            output = ".config/zen/theme/userContent.css";
            reload = "${setup}/bin/app-theme-setup zen-browser";
            renderers = {
              noctalia = {
                source = ../../configs/zen-browser/reactive-content.css;
                sharedWith = [
                  "illogical-impulse"
                  "serpantinum"
                  "end4-pc"
                  "dms"
                ];
              };
              caelestia.source = ../../configs/zen-browser/caelestia-content.css;
            };
          }
        ];
      };
  };
}
