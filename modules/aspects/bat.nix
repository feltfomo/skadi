{ program, rootPath, ... }:
{
  den.aspects.bat = program {
    imports = [
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
            "dms"
            "illogical-impulse"
            "end4-pc"
          ];
        };
        caelestia.source = "${rootPath}/configs/bat/caelestia.tmTheme";
      };
    };
  };
}
