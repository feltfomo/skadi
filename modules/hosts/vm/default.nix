# throwaway vm host for testing the installer end-to-end in qemu without touching
# real hardware. same disko/luks/impermanence/sops flow as the real hosts, but the
# disk is /dev/vda (virtio) and there's no nvidia/steam/gpu.
# install from the iso with `skadi-install vm`
{ den, inputs, ... }:
{
  den.hosts.x86_64-linux.vm = {
    users.feltfomo = { };
  };

  den.aspects.vm = {
    includes = with den.aspects; [
      base # system + impermanence + sops + graalvm + thunar
    ];

    nixos.imports = [
      inputs.disko.nixosModules.disko
      ./_nixos/disko.nix
      ./_nixos/hardware.nix
      ./_nixos/networking.nix
      ./_nixos/test-identity.nix
    ];

    # keep the vm bootloader local so installer tests boot end-to-end in qemu.
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
