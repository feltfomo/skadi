_: {
  den.aspects.shell.homeManager =
    { pkgs, ... }:
    {
      programs.fish = {
        enable = true;

        interactiveShellInit = ''
          set -g fish_greeting
          fastfetch
        '';

        shellAliases = {
          ls = "eza --icons=always";
          ln = "eza --icons=always --long";
          lt = "eza --icons=always --tree";
          ltn = "eza --icons=always --tree -long";
        };
      };

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
}
