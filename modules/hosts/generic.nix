# generic install target for a stranger's machine -- no committed
# _<host>/{disko,hardware}.nix. the disk device and hardware profile are discovered
# at install time: skadi-install detects the disk (-> _generic/device), runs
# nixos-generate-config (-> _generic/hardware.nix), git-adds them, then runs the
# ordinary flow (disko --flake .#generic -> provision -> two-step build) unchanged.
# the committed _generic/device sentinel + minimal hardware.nix exist only so
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
      ./_generic/disko.nix
      ./_generic/hardware.nix
      ./_generic/networking.nix
      ./_generic/vm-test-hooks.nix
    ];
  };
}
