_: {
  # QEMU user-net gives DHCP on the virtio nic; bootstrap-repos needs it at boot.
  networking = {
    hostName = "vm";
    networkmanager.enable = true;
  };
}
