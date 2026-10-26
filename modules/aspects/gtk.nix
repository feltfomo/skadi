{ lexicon, rootPath, ... }:
{
  den.aspects.gtk-theme = lexicon {
    homeManager =
      { pkgs, lib, ... }:
      let
        theme = pkgs.callPackage ../../pkgs/skadi-gtk-theme { };
      in
      {
        home.activation.skadiGtkTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          run ${theme}/bin/skadi-gtk-apply
        '';
      };
    theme =
      { pkgs, ... }:
      let
        theme = pkgs.callPackage ../../pkgs/skadi-gtk-theme { };
      in
      {
        id = "gtk";
        templates = [
          {
            subId = "gtk3";
            output = ".config/gtk-3.0/reactive.css";
            placedAs = "gtk3.css";
            renderers = {
              noctalia = {
                source = "${rootPath}/configs/gtk/reactive-gtk3.css";
                sharedWith = [
                  "illogical-impulse"
                  "serpantinum"
                  "end4-pc"
                  "dms"
                ];
              };
              caelestia.source = "${rootPath}/configs/gtk/caelestia-gtk3.css";
            };
          }
          {
            subId = "gtk4";
            output = ".config/gtk-4.0/reactive.css";
            reload = "${theme}/bin/skadi-gtk-apply";
            placedAs = "gtk4.css";
            renderers = {
              noctalia = {
                source = "${rootPath}/configs/gtk/reactive-gtk4.css";
                sharedWith = [
                  "illogical-impulse"
                  "serpantinum"
                  "end4-pc"
                  "dms"
                ];
              };
              caelestia.source = "${rootPath}/configs/gtk/caelestia-gtk4.css";
            };
          }
        ];
      };
  };
}
