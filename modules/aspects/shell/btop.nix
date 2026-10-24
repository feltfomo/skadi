{ lexicon, rootPath, ... }:
{
  den.aspects.btop = lexicon {
    furnish.directories = [
      {
        source = "${rootPath}/configs/btop";
        destination = ".config/btop";
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
            "illogical-impulse"
            "serpantinum"
            "end4-pc"
            "dms"
          ];
        };
        caelestia.source = "${rootPath}/configs/btop/caelestia.theme";
      };
    };
  };
}
