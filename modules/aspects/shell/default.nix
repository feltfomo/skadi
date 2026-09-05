{ den, ... }:
{
  imports = [
    ./bat.nix
    ./btop.nix
    ./cava.nix
    ./delta.nix
    ./fastfetch.nix
    ./fish.nix
    ./fzf.nix
    ./packages.nix
    ./zoxide.nix
  ];

  den.aspects.shell = {
    includes = with den.aspects; [
      fastfetch
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
