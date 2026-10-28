{ den, ... }:
{
  den.aspects.shell = {
    includes = with den.aspects; [
      starship
      btop
      cava
      fish
    ];

    homeManager.programs.nix-your-shell = {
      enable = true;
      enableFishIntegration = true;
      nix-output-monitor.enable = true;
    };
  };
}
