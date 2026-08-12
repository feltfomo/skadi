{
  lib,
  modulesPath,
  pkgs,
  ...
}:
{
  # auto-detected hardware modules
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

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

  # keep intel cpu microcode up to date
  hardware.cpu.intel.updateMicrocode = true;
  hardware.firmware = [ pkgs.sof-firmware ];
  boot.kernelParams = [ "snd_intel_dspcfg.dsp_driver=3" ];

  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="pci", KERNEL=="0000:00:1f.3", ATTR{power/control}="on"
  '';

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  services.pipewire.wireplumber.extraConfig."51-disable-suspend" = {
    "monitor.alsa.rules" = [
      {
        matches = [
          { "node.name" = "~alsa_output.*"; }
          { "node.name" = "~alsa_input.*"; }
        ];
        actions = {
          update-props = {
            "session.suspend-timeout-seconds" = 0;
          };
        };
      }
    ];
  };

}
