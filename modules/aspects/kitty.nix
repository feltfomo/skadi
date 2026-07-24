{
  program,
  rootPath,
  ...
}:
{
  # kitty claims no host or user, so it is globally owned.
  den.aspects.kitty = program {
    pkg = pkgs: pkgs.kitty;
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
    nixos =
      { config, pkgs }:
      [
        {
          imports = [ ../_lib/furnish/runtime.nix ];
          lexicon.furnish.declarations = [
            {
              label = "kitty.files[0]";
              filesystemNamespace = "${pkgs.stdenv.hostPlatform.system}/${config.networking.hostName}";
              authority = {
                scope = "user";
                identity = "feltfomo";
              };
              managedRoot = "/home/feltfomo";
              destination = ".config/kitty/kitty.conf";
              representation = "symlink";
              source = {
                kind = "path";
                value = ../../configs/kitty/kitty.conf;
              };
              provenance.source = "modules/aspects/kitty.nix";
            }
          ];
        }
      ];
  };
}
