{ lib, pkgs, ... }:
let
  # Gated on IN_DISKO_TEST, materialized as a committed sentinel so the plain
  # `nixosConfigurations.generic` eval stays PURE (no --impure). Committed "0";
  # the vm-test branch of skadi-install writes "1" here (git-added) iff
  # IN_DISKO_TEST=1, exactly like _generic/device. OFF on real hardware.
  vmTest = (lib.fileContents ./vm-test) == "1";
in
lib.mkIf vmTest {
  boot.kernelParams = [
    "console=tty0"
    "console=ttyS0,115200"
  ];
  boot.initrd.systemd.contents."/luks.key".source = pkgs.writeText "vm-luks-key" "disko";
  boot.initrd.luks.devices.cryptroot.keyFile = "/luks.key";
}
