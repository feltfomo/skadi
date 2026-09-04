{ lib, pkgs, ... }:
let
  # a committed sentinel keeps generic evaluation pure.
  # vm-test writes one only when IN_DISKO_TEST is enabled.
  vmTest = (lib.fileContents ../vm-test) == "1";
in
lib.mkIf vmTest {
  boot.kernelParams = [
    "console=tty0"
    "console=ttyS0,115200"
  ];
  boot.initrd.systemd.contents."/luks.key".source = pkgs.writeText "vm-luks-key" "disko";
  boot.initrd.luks.devices.cryptroot.keyFile = "/luks.key";
}
