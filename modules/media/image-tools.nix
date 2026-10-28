{
  den.aspects.image-tools.homeManager = { pkgs, ... }: {
    home.packages = [
      pkgs.imagemagick
      # gifski 1.34.0 intermittently failed its timing test.
      (pkgs.gifski.overrideAttrs (_: {
        doCheck = false;
      }))
    ];
  };
}
