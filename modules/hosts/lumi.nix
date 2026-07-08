{ den, inputs, ... }:
{
  den.hosts.x86_64-linux.lumi = {
    users.feltfomo = { };
    users.grandpa = { };
  };

  # den activates the host aspect, so feature includes go here. includes on
  # the host entity are inert freeform metadata.
  den.aspects.lumi = {
    includes = [
      den.aspects.base
      den.aspects.gnome
      den.aspects.networking
    ];

    # disko's nixos module must sit with the disko.devices it enables
    nixos.imports = [
      inputs.disko.nixosModules.disko
      ./_lumi/disko.nix
      ./_lumi/hardware.nix
    ];

    # bootloader is a per-host machine fact. lumi was installed with
    # systemd-boot (EFI vars written, ESP at /boot), so it keeps systemd-boot
    # rather than inheriting the universal GRUB -- matches the live install.
    nixos.boot.loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
  };
}
