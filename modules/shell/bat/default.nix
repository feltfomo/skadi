{ config, lexicon, ... }:
{
  den.aspects.bat = lexicon {
    homeManager.imports = [
      {
        programs.bat = {
          enable = true;
          config.theme = "reactive";
        };
      }
    ];
    theme = {
      id = "bat";
      output = ".config/bat/themes/reactive.tmTheme";
      reload = "bat cache --build";
      renderers = {
        noctalia = {
          source = ./config/reactive.tmTheme;
          sharedWith = config.skadi.theme.noctaliaCompatibleRenderers;
        };
        caelestia.source = ./config/caelestia.tmTheme;
      };
    };
  };
}
