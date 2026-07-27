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
        # furnish owns this destination's lifecycle instead of hjem. the key goes
        # away when the generated path is the only path and every file entry is
        # furnish-owned by default.
        furnishManaged = true;
        label = "kitty.files[0]";
        provenance = "modules/aspects/kitty.nix";
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
