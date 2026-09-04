{ den, inputs, ... }:
{
  den.hosts.x86_64-linux.lumi = {
    users.feltfomo = { };
    users.grandpa = { };
  };

  # den activates the host aspect, so feature includes go here. includes on
  # the host entity are inert freeform metadata.
  den.aspects.lumi = {
    includes = with den.aspects; [
      base
      gnome
      networking
      wayland
    ];

    # disko's nixos module must sit with the disko.devices it enables
    nixos.imports = [
      inputs.disko.nixosModules.disko
      ./_nixos/disko.nix
      ./_nixos/hardware.nix
    ];

    # lumi boots efi grub from the esp at /boot with a managed nvram entry.
    # wrong-scout briefly installed systemd-boot here; remove its files and
    # "linux boot manager" nvram entry before applying with boot and reboot.
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
