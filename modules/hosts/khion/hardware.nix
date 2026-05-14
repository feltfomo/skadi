{ ... }:
{
  flake.nixosModules.khionHardware =
    { lib, modulesPath, ... }:
    {
      # auto-detected hardware modules
      imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

      # hardware-specific kernel modules and platform
      boot.initrd.availableKernelModules = [
        "nvme"
        "xhci_pci"
        "ahci"
        "usb_storage"
        "usbhid"
        "sd_mod"
      ];
      boot.kernelModules = [ "kvm-amd" ];
      nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
    };
}
