{ lexicon, ... }:
{
  den.aspects.equibop = lexicon {
    package = pkgs: pkgs.equibop;
    homeManager =
      { pkgs, lib, ... }:
      let
        setup = pkgs.skadi-app-theme-setup;
      in
      {
        home.activation.equibopTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          run ${setup}/bin/app-theme-setup equibop
        '';
      };
    theme =
      { pkgs, ... }:
      let
        setup = pkgs.skadi-app-theme-setup;
        stylesheet = palette: toString (pkgs.callPackage ./config/_system24.nix { inherit palette; });
      in
      {
        id = "equibop";
        output = ".config/equibop/themes/reactive.theme.css";
        reload = "${setup}/bin/app-theme-setup equibop";
        renderers = {
          noctalia = {
            source = stylesheet ./config/reactive.css;
            placedAs = "reactive.css";
            sharedWith = [
              "illogical-impulse"
              "serpantinum"
              "end4-pc"
              "dms"
            ];
          };
          caelestia = {
            source = stylesheet ./config/caelestia.css;
            placedAs = "caelestia.css";
          };
        };
      };
  };
}
