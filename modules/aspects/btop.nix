{ program, rootPath, ... }:
{
  den.aspects.btop = program {
    directories = [
      {
        src = "${rootPath}/configs/btop";
        dest = ".config/btop";
      }
    ];
    theme = {
      id = "btop";
      output = ".config/btop/themes/reactive.theme";
      reload = ''nu "$HOME/.config/btop/apply.nu"'';
      renderers = {
        noctalia = {
          source = "${rootPath}/configs/btop/reactive.theme";
          sharedWith = [
            "dms"
            "illogical-impulse"
            "end4-pc"
          ];
        };
        caelestia.source = "${rootPath}/configs/btop/caelestia.theme";
      };
    };
  };
}
