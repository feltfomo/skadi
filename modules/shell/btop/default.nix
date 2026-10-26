{ lexicon, ... }:
{
  den.aspects.btop = lexicon {
    furnish.directories = [
      {
        source = ./config;
        destination = ".config/btop";
      }
    ];
    theme = {
      id = "btop";
      output = ".config/btop/themes/reactive.theme";
      reload = ''nu "$HOME/.config/btop/apply.nu"'';
      renderers = {
        noctalia = {
          source = ./config/reactive.theme;
          sharedWith = [
            "illogical-impulse"
            "serpantinum"
            "end4-pc"
            "dms"
          ];
        };
        caelestia.source = ./config/caelestia.theme;
      };
    };
  };
}
