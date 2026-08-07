{ den, ... }:
{
  den.aspects.shell = {
    includes = with den.aspects; [
      fish
    ];

    homeManager =
      { pkgs, ... }:
      {
        programs.nix-your-shell = {
          enable = true;
          enableFishIntegration = true;
          nix-output-monitor.enable = true;
        };

        home.packages = with pkgs; [
          fd
          eza
          ripgrep
        ];
      };
  };
}
