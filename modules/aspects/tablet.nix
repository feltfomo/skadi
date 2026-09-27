{
  den.aspects.tablet.nixos = {
    hardware = {
      opentabletdriver.enable = true;
      uinput.enable = true;
    };
    boot.kernelModules = [ "uinput" ];
  };
}
