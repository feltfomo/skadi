{
  lexicon,
  inputs,
  ...
}:
{
  den.aspects.zen-browser = lexicon {
    package = pkgs: inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.twilight;
    homeManager =
      { pkgs, lib, ... }:
      let
        setup = pkgs.skadi-app-theme-setup;
      in
      {
        home.activation.zenBrowserTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          run ${setup}/bin/app-theme-setup zen-browser
        '';
      };
    theme =
      { pkgs, ... }:
      let
        setup = pkgs.skadi-app-theme-setup;
      in
      {
        id = "zen-browser";
        templates = [
          {
            output = ".config/zen/theme/palette.css";
            reload = "${setup}/bin/app-theme-setup zen-browser";
            renderers = {
              noctalia = {
                source = ./config/reactive-palette.css;
                sharedWith = [
                  "illogical-impulse"
                  "serpantinum"
                  "end4-pc"
                  "dms"
                ];
              };
              caelestia.source = ./config/caelestia-palette.css;
            };
          }
          {
            subId = "content";
            output = ".config/zen/theme/userContent.css";
            reload = "${setup}/bin/app-theme-setup zen-browser";
            renderers.noctalia = {
              source = ./config/theme/userContent.css;
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
              source = ./config/theme/userChrome.css;
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
          source = ./config/theme + "/${name}.css";
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
