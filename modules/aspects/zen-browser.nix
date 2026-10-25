{
  lexicon,
  rootPath,
  inputs,
  ...
}:
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
            output = ".config/zen/theme/palette.css";
            reload = "${setup}/bin/app-theme-setup zen-browser";
            renderers = {
              noctalia = {
                source = ../../configs/zen-browser/reactive-palette.css;
                sharedWith = [
                  "illogical-impulse"
                  "serpantinum"
                  "end4-pc"
                  "dms"
                ];
              };
              caelestia.source = ../../configs/zen-browser/caelestia-palette.css;
            };
          }
          {
            subId = "content";
            output = ".config/zen/theme/userContent.css";
            reload = "${setup}/bin/app-theme-setup zen-browser";
            renderers.noctalia = {
              source = ../../configs/zen-browser/theme/userContent.css;
              sharedWith = [
                "illogical-impulse"
                "serpantinum"
                "caelestia"
                "end4-pc"
                "dms"
              ];
            };
          }
          {
            subId = "chrome";
            output = ".config/zen/theme/userChrome.css";
            reload = "${setup}/bin/app-theme-setup zen-browser";
            renderers.noctalia = {
              source = ../../configs/zen-browser/theme/userChrome.css;
              sharedWith = [
                "illogical-impulse"
                "serpantinum"
                "caelestia"
                "end4-pc"
                "dms"
              ];
            };
          }
        ];
      };

    furnish.files =
      map
        (name: {
          source = "${rootPath}/configs/zen-browser/theme/${name}.css";
          destination = ".config/zen/theme/${name}.css";
          representation = "writable";
          onConflict = "source-wins";
        })
        [
          "materials"
          "content"
          "chrome"
          "panels"
          "urlbar"
          "tabs"
        ];
  };
}
