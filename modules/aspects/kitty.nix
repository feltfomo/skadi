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
    theme.noctalia = {
      id = "kitty";
      source = "${rootPath}/configs/kitty/themes/skadi.conf";
      output = ".config/kitty/themes/skadi.conf";
      reload = "pkill -SIGUSR1 kitty";
    };
  };
}
