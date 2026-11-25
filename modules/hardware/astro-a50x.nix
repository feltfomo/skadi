_: {
  # in Xbox mode the A50 X base station speaks GIP on its USB-C port, not USB
  # audio class, so snd-usb-audio never claims it. xone-wired matches every
  # Logitech 0xff/0x47/0xd0 interface and exposes the headset as an ALSA card.
  den.aspects.astro-a50x.nixos = {
    hardware.xone.enable = true;
  };
}
