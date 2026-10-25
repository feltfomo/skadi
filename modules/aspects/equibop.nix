{ lexicon, ... }:
{
  den.aspects.equibop = lexicon {
    package = pkgs: pkgs.equibop;
    homeManager =
      { pkgs, lib, ... }:
      let
        setup = import ../../lib/theme-setup.nix { inherit pkgs; };
      in
      {
        home.activation.equibopTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          run ${setup}/bin/app-theme-setup equibop
        '';
      };
    theme =
      { pkgs, ... }:
      let
        setup = import ../../lib/theme-setup.nix { inherit pkgs; };
        stylesheet =
          palette: toString (pkgs.callPackage ../../configs/equibop/system24.nix { inherit palette; });
      in
      {
        id = "equibop";
        output = ".config/equibop/themes/reactive.theme.css";
        reload = "${setup}/bin/app-theme-setup equibop";
        renderers = {
          noctalia = {
            source = stylesheet ../../configs/equibop/reactive.css;
            placedAs = "reactive.css";
            sharedWith = [
              "illogical-impulse"
              "serpantinum"
              "end4-pc"
              "dms"
            ];
          };
          caelestia = {
            source = stylesheet ../../configs/equibop/caelestia.css;
            placedAs = "caelestia.css";
          };
        };
      };
  };
}
