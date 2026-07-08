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

    # first-activation collision nets for the 123-commit catch-up switch.
    # feltfomo's dotfiles change ownership between home-manager and hjem across
    # the jump (e.g. fuzzel/walker move to hjem), so let each tool take over the
    # other's pre-existing files instead of aborting the first activation:
    # home-manager backs up any foreign file it must replace (*.hm-bak), and hjem
    # clobbers any foreign file it must replace. lumi-only -- khion keeps the
    # defaults (no backup extension, clobber off).
    nixos.home-manager.backupFileExtension = "hm-bak";
    nixos.hjem.clobberByDefault = true;
  };
}
