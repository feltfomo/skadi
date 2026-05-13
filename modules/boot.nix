{ ... }:
{
  flake.nixosModules.boot =
    { ... }:
    {
      boot.loader = {
        grub = {
          enable = true;
          device = "nodev";
          efiSupport = true;
        };
        efi = {
          canTouchEfiVariables = true;
        };
      };
    };
}
