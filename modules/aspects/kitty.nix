{
  program,
  rootPath,
  ...
}:
{
  # kitty claims no host or user, so it is globally owned.
  den.aspects.kitty = program {
    pkg = pkgs: pkgs.kitty;
    directories = [
      {
        src = "${rootPath}/configs/kitty";
        dest = ".config/kitty";
      }
    ];
    theme = {
      id = "kitty";
      renderers = {
        noctalia = {
          source = "${rootPath}/configs/kitty/themes/skadi.conf";
          output = ".config/kitty/themes/skadi.conf";
          reload = "pkill -SIGUSR1 kitty";
        };
        dms = {
          source = "${rootPath}/configs/kitty/themes/skadi.conf";
          output = ".config/kitty/themes/skadi.conf";
          reload = "pkill -SIGUSR1 kitty";
        };
        illogical-impulse = {
          source = "${rootPath}/configs/kitty/themes/skadi.conf";
          output = ".config/kitty/themes/skadi.conf";
          reload = "pkill -SIGUSR1 kitty";
        };
        end4-pc = {
          source = "${rootPath}/configs/kitty/themes/skadi.conf";
          output = ".config/kitty/themes/skadi.conf";
          reload = "pkill -SIGUSR1 kitty";
        };
        caelestia = {
          source = "${rootPath}/configs/kitty/themes/caelestia.conf";
          output = ".config/kitty/themes/skadi.conf";
          placedAs = "theme.conf";
          reload = "pkill -SIGUSR1 kitty";
        };
      };
    };
  };
}
