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
      output = ".config/kitty/themes/reactive.conf";
      reload = "pkill -SIGUSR1 kitty";
      renderers = {
        noctalia = {
          source = "${rootPath}/configs/kitty/themes/reactive.conf";
          sharedWith = [
            "dms"
            "illogical-impulse"
            "end4-pc"
          ];
        };
        caelestia.source = "${rootPath}/configs/kitty/themes/caelestia.conf";
      };
    };
  };
}
