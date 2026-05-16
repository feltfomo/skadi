{ config, ... }:
{
  flake.modules.nixos.kitty =
    { pkgs, ... }:
    {
      imports = [
        (config.flake.factory.terminal {
          name = "kitty";
          pkg = pkgs.kitty;
          configPath = ../configs/kitty;
          templateFile = ../configs/kitty/themes/skadi.conf;
        })
      ];
    };
}
