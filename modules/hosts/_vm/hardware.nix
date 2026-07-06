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

  # vm-test runs QEMU headless with ttyS0 redirected to a file and greps it for
  # a login prompt; with no serial console the guest reaches userspace but the
  # harness can't see it. Real hosts never import this module, so it stays
  # VM-only. tty0 first so a graphical console still works if one is attached.
  boot.kernelParams = [ "console=tty0" "console=ttyS0,115200" ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
