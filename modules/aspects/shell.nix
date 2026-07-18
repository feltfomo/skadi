_: {
  den.aspects.shell.homeManager =
    { pkgs, ... }:
    {
      programs.fish = {
        enable = true;

        interactiveShellInit = ''
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
        eza
        # fd + ripgrep: general shell tools that also power nvim's telescope
        fd
        ripgrep
      ];
    };
}
