{
  den.aspects.screen-capture.homeManager = { pkgs, ... }: {
    home.packages = with pkgs; [
      tesseract
      slurp
      grim
    ];
  };
}
