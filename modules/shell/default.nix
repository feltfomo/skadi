{ den, ... }:
{
  den.aspects.shell = {
    includes = with den.aspects; [
      fastfetch
      starship
      btop
      cava
      fish
      bat
    ];

    homeManager.programs.nix-your-shell = {
      enable = true;
      enableFishIntegration = true;
      nix-output-monitor.enable = true;
    };
  };
}
