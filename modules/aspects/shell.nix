_: {
  den.aspects.shell.homeManager =
    { pkgs, ... }:
    {
      programs.fish = {
        enable = true;

        # launch terminal with fastfetch
        interactiveShellInit = ''
          fastfetch
        '';

        shellAliases = {
          ls = "eza --icons";
          ln = "eza --icons --long";
          lt = "eza --icons --tree";
          ltn = "eza --icons --tree -long";
        };
      };

      # nix your shell
      programs.nix-your-shell = {
        enable = true;
        enableFishIntegration = true;
        nix-output-monitor.enable = true;
      };

      home.packages = with pkgs; [
        eza
      ];
    };
}
