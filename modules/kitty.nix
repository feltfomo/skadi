{ config, inputs, ... }:
{
  flake.modules.nixos.kitty =
    { pkgs, ... }:
    {
      imports = [
        (config.flake.factory.program {
          pkg = pkgs.kitty;
          imports = [ inputs.self.modules.nixos.terminalPackages ];
          files = [
            {
              dest = ".config/kitty/kitty.conf";
              src = ../configs/kitty/kitty.conf;
            }
          ];
          templates = [
            {
              name = "kitty.conf";
              templateFile = ../configs/kitty/themes/skadi.conf;
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
        })
      ];
    };
}
