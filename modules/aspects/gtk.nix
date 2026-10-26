{ lexicon, rootPath, ... }:
{
  den.aspects.gtk-theme = lexicon {
    homeManager =
      { pkgs, lib, ... }:
      let
        theme = pkgs.callPackage ../../pkgs/skadi-gtk-theme { };
      in
      {
        gtk.gtk3.extraConfig.gtk-modules = "${pkgs.skadi-gtk-reload}/lib/gtk-3.0/modules/libskadi-palette-reload.so";
        # gtk 4 has no gtk-modules setting; it finds the module through the profile's GTK_PATH.
        home.packages = [ pkgs.skadi-gtk-reload ];
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
