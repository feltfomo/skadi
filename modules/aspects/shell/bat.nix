{ lexicon, rootPath, ... }:
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
          source = "${rootPath}/configs/bat/reactive.tmTheme";
          sharedWith = [
            "illogical-impulse"
            "serpantinum"
            "end4-pc"
            "dms"
          ];
        };
        caelestia.source = "${rootPath}/configs/bat/caelestia.tmTheme";
      };
    };
  };
}
