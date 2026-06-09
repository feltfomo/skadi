_: {
  den.aspects.docker.nixos = {
    # rootful docker, prunes dangling images weekly like the nix gc
    virtualisation.docker = {
      enable = true;
      autoPrune = {
        enable = true;
        dates = "weekly";
      };
    };
  };
}
