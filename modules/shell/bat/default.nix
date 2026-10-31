{ lexicon, ... }:
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
      template = ./config/reactive.tmTheme;
    };
  };
}
