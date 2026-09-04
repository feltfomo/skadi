{
  lib,
  pkgs,
  modulesPath,
  ...
}:
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

  # vm-test needs ttyS0 for headless boot diagnostics.
  # tty0 keeps an attached graphical console usable.
  boot.kernelParams = [
    "console=tty0"
    "console=ttyS0,115200"
  ];

  # vm-test enrolls the deterministic disko key without a trailing newline.
  # the vm-only initrd keyfile matches it for unattended boot.
  boot.initrd.systemd.contents."/luks.key".source = pkgs.writeText "vm-luks-key" "disko";
  boot.initrd.luks.devices.cryptroot.keyFile = "/luks.key";

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
