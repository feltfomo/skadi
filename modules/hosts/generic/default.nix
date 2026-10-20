# generic discovers its disk device and hardware profile during installation.
# committed sentinels exist only so `nix flake check` can evaluate the host.
# install from the iso with `skadi-install generic`
{ den, inputs, ... }:
{
  den.hosts.x86_64-linux.generic = {
    users.owner = { };
  };

  den.aspects.generic = {
    includes = [
      den.aspects.base
    ];

    nixos.imports = [
      inputs.disko.nixosModules.disko
      ./_nixos/vm-test-hooks.nix
      ./_nixos/networking.nix
      ./_nixos/hardware.nix
      ./_nixos/disko.nix
    ];

    # keep generic's bootloader outside regenerated hardware configuration.
    nixos.boot.loader = {
      grub = {
        enable = true;
        device = "nodev";
        efiSupport = true;
      };
      efi.canTouchEfiVariables = true;
    };
  };
}
