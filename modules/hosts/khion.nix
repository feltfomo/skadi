{ den, inputs, ... }:
{
  den.hosts.x86_64-linux.khion = {
    users.feltfomo = { };
  };

  # den activates the host aspect, so feature includes go here. includes on
  # the host entity are inert freeform metadata.
  den.aspects.khion = {
    includes = [
      den.aspects.base
      den.aspects.docker
      den.aspects.gpu-nvidia
      den.aspects.hermes
      den.aspects.networking
      den.aspects.notion-sync
      den.aspects.steam
      den.aspects.tailscale
      den.aspects.wayland
      den.aspects.noctalia-greeter
    ];

    # disko's nixos module must sit with the disko.devices it enables
    nixos.imports = [
      inputs.disko.nixosModules.disko
      ./_khion/disko.nix
      ./_khion/hardware.nix
    ];

    # bootloader is a per-host machine fact. relocated verbatim out of the
    # universal system aspect so lumi can use systemd-boot without inheriting
    # khion's GRUB; khion's resolved boot.loader is unchanged (byte-identical).
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
