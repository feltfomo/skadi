{
  # qemu user networking provides dhcp for the virtio interface at boot.
  networking = {
    hostName = "vm";
    networkmanager.enable = true;
  };
}
