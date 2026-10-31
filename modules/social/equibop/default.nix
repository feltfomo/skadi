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
      in
      {
        id = "equibop";
        output = ".config/equibop/themes/reactive.theme.css";
        reload = "${setup}/bin/app-theme-setup equibop";
        template = ./config/reactive.css;
        transform = palette: pkgs.callPackage ./config/_system24.nix { inherit palette; };
      };
  };
}
