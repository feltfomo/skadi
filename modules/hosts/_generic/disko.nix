{ lib, ... }:
let
  # DISCOVERED at install time: skadi-install writes the detected disk here
  # (git-added) before `disko --flake .#generic`. The committed sentinel is ONLY
  # for `nix flake check`; the installer asserts a real device first, so this
  # value never reaches a live disko run. fileContents strips the trailing NL.
  device = lib.fileContents ./device;
in
{
  disko.devices.disk.main = {
    type = "disk";
    device = device;
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        luks = {
          size = "100%";
          content = {
            type = "luks";
            name = "cryptroot";
            settings.allowDiscards = true;
            content = {
              type = "btrfs";
              extraArgs = [ "-L" "nixos" "-f" ];
              subvolumes = {
                "@" = { mountpoint = "/"; mountOptions = [ "compress=zstd" "noatime" ]; };
                "@nix" = { mountpoint = "/nix"; mountOptions = [ "compress=zstd" "noatime" ]; };
                "@persist" = { mountpoint = "/persist"; mountOptions = [ "compress=zstd" "noatime" ]; };
                "@home" = { mountpoint = "/home"; mountOptions = [ "compress=zstd" "noatime" ]; };
                "@swap" = { mountpoint = "/.swapvol"; swap.swapfile.size = "8G"; };
                "@blank" = { };
              };
            };
          };
        };
      };
    };
  };
}