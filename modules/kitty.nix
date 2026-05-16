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
        })
      ];
    };
}
