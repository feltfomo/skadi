{
  den.aspects.grub.nixos.boot.loader = {
    grub = {
      enable = true;
      device = "nodev";
      efiSupport = true;
      # early nvidia puts its gsp firmware in every initrd, and the 1G esp holds only a few of those.
      configurationLimit = 5;
    };
    # long enough to reach the menu, short enough not to wait on it.
    timeout = 2;
    efi.canTouchEfiVariables = true;
  };
}
