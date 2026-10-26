{ config, lexicon, ... }:
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
          sharedWith = config.skadi.theme.noctaliaCompatibleRenderers;
        };
        caelestia.source = ./config/caelestia.theme;
      };
    };
  };
}
