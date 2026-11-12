{
  lib,
  modulesPath,
  ...
}:
{
  # auto-detected hardware modules
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    ./audio
  ];

  # hardware-specific kernel modules and platform
  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "nvme"
    "usb_storage"
    "sd_mod"
    "sdhci_pci"
    "rtsx_usb_sdmmc"
  ];
  boot.kernelModules = [ "kvm-intel" ];
  # early kms, so plymouth draws the disk password prompt at the panel's native mode.
  boot.initrd.kernelModules = [ "i915" ];

  # keep intel cpu microcode up to date
  hardware.cpu.intel.updateMicrocode = true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

}
