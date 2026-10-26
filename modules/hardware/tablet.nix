{
  den.aspects.tablet.nixos = {
    hardware = {
      opentabletdriver = {
        enable = true;
        # osu! lazer bundles its own OpenTabletDriver and reads hidraw directly.
        # disable the daemon to avoid competing for the device and moving the
        # desktop pointer. keep the udev rules and wacom blacklist.
        daemon.enable = false;
      };
      uinput.enable = true;
    };
    boot.kernelModules = [ "uinput" ];
  };
}
