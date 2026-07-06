{ lib, modulesPath, ... }:
{
  # PLACEHOLDER. skadi-install overwrites this with `nixos-generate-config
  # --show-hardware-config` for the real target at install time. Committed only
  # so `nix flake check` can evaluate nixosConfigurations.generic; kept minimal +
  # plain UEFI/x86_64. Test-only console/keyfile hooks live in ./vm-test-hooks.nix,
  # NOT here, so the regenerated file stays pure (per [G3]).
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];
  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "ahci"
    "usb_storage"
    "usbhid"
    "sd_mod"
    "sr_mod"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
