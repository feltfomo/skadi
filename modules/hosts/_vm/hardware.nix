{ lib, modulesPath, ... }:
{
  # qemu-guest pulls the virtio stack; no nvme/nvidia/ckb-next like real hosts.
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  boot.initrd.availableKernelModules = [
    "virtio_pci"
    "virtio_blk"
    "virtio_scsi"
    "ahci"
    "sd_mod"
    "sr_mod"
  ];
  boot.kernelModules = [ ];
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
