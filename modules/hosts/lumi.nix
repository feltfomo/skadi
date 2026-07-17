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
      ./_lumi/disko.nix
      ./_lumi/hardware.nix
    ];

    # bootloader is a per-host machine fact. lumi is a UEFI laptop (ESP at
    # /boot) using EFI GRUB. the firmware honors the UEFI BootOrder (confirmed:
    # lumi booted its first BootOrder entry), so GRUB gets a real NVRAM entry
    # that NixOS manages via canTouchEfiVariables -- no removable-fallback hack.
    # NOTE: the wrong-scout catch-up briefly installed systemd-boot here; a
    # leftover /EFI/systemd + /boot/loader + "Linux Boot Manager" NVRAM entry
    # must be removed by hand (NixOS never uninstalls a foreign loader). apply
    # with `nixos-rebuild boot` + reboot, never a live `switch`.
    nixos.boot.loader = {
      grub = {
        enable = true;
        device = "nodev";
        efiSupport = true;
      };
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
