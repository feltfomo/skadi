_: {
  # the PRO 2's faulty wheel switch sends middle clicks that paste the primary
  # selection. suppress HID button 3 on the Lightspeed receiver until the
  # switch is cleaned or replaced.
  den.aspects.logitech-pro2.nixos = {
    services.udev.extraHwdb = ''
      evdev:input:b0003v046Dp40A8*
       KEYBOARD_KEY_90003=reserved
    '';
  };
}
