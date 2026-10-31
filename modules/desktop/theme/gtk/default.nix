{ lexicon, ... }:
{
  skadi.packages.skadi-gtk-theme = ./_package.nix;

  den.aspects.gtk-theme = lexicon {
    homeManager =
      { pkgs, lib, ... }:
      let
        theme = pkgs.skadi-gtk-theme;
      in
      {
        home.activation.skadiGtkTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          run ${theme}/bin/skadi-gtk-apply
        '';
      };
    theme =
      { pkgs, ... }:
      let
        theme = pkgs.skadi-gtk-theme;
      in
      {
        id = "gtk";
        templates = [
          {
            subId = "gtk3";
            output = ".config/gtk-3.0/reactive.css";
            placedAs = "gtk3.css";
            template = ./config/reactive-gtk3.css;
          }
          {
            subId = "gtk4";
            output = ".config/gtk-4.0/reactive.css";
            reload = "${theme}/bin/skadi-gtk-apply";
            placedAs = "gtk4.css";
            template = ./config/reactive-gtk4.css;
          }
        ];
      };
  };
}
