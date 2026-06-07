_: {
  den.aspects.steam.nixos =
    { pkgs, ... }:
    {
      # install steam, extest, protontricks, and proton-ge to play window games
      programs.steam = {
        enable = true;
        extest.enable = true;
        protontricks.enable = true;
        extraCompatPackages = with pkgs; [
          proton-ge-bin
        ];
      };
    };
}
