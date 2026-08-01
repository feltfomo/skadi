{
  program,
  rootPath,
  ...
}:
{
  # kitty claims no host or user, so it is globally owned.
  den.aspects.kitty = program {
    pkg = pkgs: pkgs.kitty;
    files = [
      {
        dest = ".config/kitty/kitty.conf";
        src = "${rootPath}/configs/kitty/kitty.conf";
      }
    ];
    theme.noctalia = {
      id = "kitty";
      source = "${rootPath}/configs/kitty/themes/skadi.conf";
      # the seed lands flat as kitty.conf; the repo source is skadi.conf
      placedAs = "kitty.conf";
      subdir = null;
      output = ".config/kitty/themes/skadi.conf";
      reload = "pkill -SIGUSR1 kitty";
    };
  };
}
