{ den, inputs, ... }:
{
  den.hosts.x86_64-linux.lumi = {
    users.feltfomo = { };
    users.grandpa = { };
  };

  # keep feature selection on the aspect so the installer can list and drop it.
  den.aspects.lumi = {
    includes = with den.aspects; [
      silent-sddm
      networking
      tailscale
      wayland
      plasma
      tablet
      base
    ];

    nixos.skadi.silent-sddm.preferredSessions = {
      feltfomo = "Hyprland";
      grandpa = "Plasma (Wayland)";
    };

    # disko's nixos module must sit with the disko.devices it enables
    nixos.imports = [
      inputs.disko.nixosModules.disko
      ./_nixos/hardware.nix
      ./_nixos/disko.nix
    ];

    # lumi boots efi grub from the esp at /boot with a managed nvram entry.
    # remove leftover systemd-boot files and its "linux boot manager" nvram
    # entry before applying with boot and reboot.
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
