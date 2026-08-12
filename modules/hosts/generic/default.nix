# generic install target for a stranger's machine. the disk device and
# hardware profile are discovered at install time: skadi-install writes
# generic/device and generic/_nixos/hardware.nix, git-adds them, then runs the
# ordinary flow (disko --flake .#generic -> provision -> two-step build).
# the committed device sentinel + minimal hardware.nix exist only so
# `nix flake check` can evaluate this host; the installer asserts a real detected
# device first, so the sentinel never reaches a live disko run.
# install from the ISO with:  skadi-install generic
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
      ./_nixos/disko.nix
      ./_nixos/hardware.nix
      ./_nixos/networking.nix
      ./_nixos/vm-test-hooks.nix
    ];

    # bootloader relocated out of the universal system aspect (khion/lumi now
    # own theirs). generic keeps the previous universal GRUB unchanged. it lives
    # here, not in _nixos/hardware.nix, because the installer regenerates that
    # file via nixos-generate-config and would clobber it.
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
