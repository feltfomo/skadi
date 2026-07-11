{
  program,
  rootPath,
  ...
}:
{
  # kitty claims no host or user, so it is globally owned -- the ownerships
  # engine resolves an untagged spec with no build ctx at all. narrowing
  # wouldn't change this shape either: program.nix takes hosts/users as claim
  # keys on the spec itself, and resolve threads host/user into the class
  # modules lazily -- see hyprland.nix, which narrows on host and still stays a
  # bare call with no { host, user }: wrapper.
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
