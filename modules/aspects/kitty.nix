{
  program,
  rootPath,
  ...
}:
{
  # kitty claims no host or user, so it is globally owned -- the ownerships
  # engine resolves an untagged spec with no build ctx, so program binds
  # directly with no { host, user }: wrapper. an aspect that narrowed on a host
  # would take the wrapper to thread its entity into resolve.
  den.aspects.kitty = program {
    pkg = pkgs: pkgs.kitty;
    files = [
      {
        dest = ".config/kitty/kitty.conf";
        src = "${rootPath}/configs/kitty/kitty.conf";
      }
    ];
    templates = [
      {
        name = "kitty.conf";
        templateFile = "${rootPath}/configs/kitty/themes/skadi.conf";
      }
    ];
    noctaliaConfig = {
      _fileName = "kitty";
      theme.templates.user.kitty = {
        input_path = "~/.config/noctalia/templates/kitty.conf";
        output_path = "~/.config/kitty/themes/skadi.conf";
        post_hook = "pkill -SIGUSR1 kitty";
      };
    };
  };
}
