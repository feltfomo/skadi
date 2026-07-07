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

  # vm-test runs QEMU headless with ttyS0 redirected to a file and greps it for
  # a login prompt; with no serial console the guest reaches userspace but the
  # harness can't see it. real hosts never import this module, so it stays
  # vm-only. tty0 first so a graphical console still works if one is attached.
  boot.kernelParams = [
    "console=tty0"
    "console=ttyS0,115200"
  ];

  # vm-test boots this disk headless with serial -> a file, so nobody can type
  # the LUKS passphrase disko sets at install time. the harness formats under
  # IN_DISKO_TEST=1 (scripts/vm-test.sh), which keys the cryptroot slot with the
  # deterministic passphrase `disko`; we embed a byte-identical keyfile in the
  # initrd and point cryptroot at it so the disk auto-unlocks and boot reaches a
  # login prompt unattended. writeText adds no trailing newline, matching disko's
  # `--key-file <(echo -n "disko")` enroll byte-for-byte. vm-only -- real hosts
  # never import _vm, so they keep their interactive passphrase.
  boot.initrd.systemd.contents."/luks.key".source = pkgs.writeText "vm-luks-key" "disko";
  boot.initrd.luks.devices.cryptroot.keyFile = "/luks.key";

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
