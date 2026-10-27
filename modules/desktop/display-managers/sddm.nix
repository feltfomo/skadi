{
  den.aspects.sddm = {
    persistence.directories = [
      {
        directory = "/var/lib/sddm";
        user = "sddm";
        group = "sddm";
        mode = "0750";
      }
    ];

    nixos.services.displayManager.sddm.enable = true;
  };
}
