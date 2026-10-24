{ lexicon, rootPath, ... }:
{
  den.aspects.gtk-theme = lexicon {
    furnish.directories = [
      {
        source = "${rootPath}/configs/gtk";
        destination = ".config/gtk-theme";
      }
    ];
    theme = {
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
          reload = ''nu "$HOME/.config/gtk-theme/apply.nu"'';
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
