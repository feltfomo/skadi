{ den, ... }:
{
  imports = [
    ./fastfetch.nix
    ./starship.nix
    ./packages.nix
    ./zoxide.nix
    ./delta.nix
    ./btop.nix
    ./cava.nix
    ./fish.nix
    ./bat.nix
    ./fzf.nix
  ];

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
