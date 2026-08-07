{
  program,
  rootPath,
  ...
}:
{
  den.aspects.ghostty = program {
    pkg = pkgs: pkgs.ghostty;
    directories = [
      {
        src = "${rootPath}/configs/ghostty";
        dest = ".config/ghostty";
      }
    ];
    theme = {
      id = "ghostty";
      renderers = {
        noctalia = {
          source = "${rootPath}/configs/ghostty/themes/skadi.conf";
          output = ".config/ghostty/themes/skadi.conf";
        };
        dms = {
          source = "${rootPath}/configs/ghostty/themes/skadi.conf";
          output = ".config/ghostty/themes/skadi.conf";
        };
        illogical-impulse = {
          source = "${rootPath}/configs/ghostty/themes/skadi.conf";
          output = ".config/ghostty/themes/skadi.conf";
        };
        end4-pc = {
          source = "${rootPath}/configs/ghostty/themes/skadi.conf";
          output = ".config/ghostty/themes/skadi.conf";
        };
        caelestia = {
          source = "${rootPath}/configs/ghostty/themes/caelestia.conf";
          output = ".config/ghostty/themes/skadi.conf";
          placedAs = "theme.conf";
        };
      };
    };
  };
}
