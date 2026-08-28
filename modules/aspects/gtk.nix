{ program, rootPath, ... }:
{
  den.aspects.gtk-theme = program {
    directories = [
      {
        src = "${rootPath}/configs/gtk";
        dest = ".config/gtk-theme";
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
                "dms"
                "illogical-impulse"
                "end4-pc"
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
                "dms"
                "illogical-impulse"
                "end4-pc"
              ];
            };
            caelestia.source = "${rootPath}/configs/gtk/caelestia-gtk4.css";
          };
        }
      ];
    };
  };
}
