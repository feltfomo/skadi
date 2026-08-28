{ den, ... }: {
  den.aspects.shell = {
    includes = with den.aspects; [
      fish
      bat
      btop
      cava
      fastfetch
    ];

    homeManager = { pkgs, ... }: {
      programs.nix-your-shell = {
        enable = true;
        enableFishIntegration = true;
        nix-output-monitor.enable = true;
      };

      programs.zoxide = {
        enable = true;
        enableFishIntegration = true;
        options = [
          "--cmd"
          "cd"
        ];
      };

      home.packages = with pkgs; [
        fd
        eza
        ripgrep
      ];
    };
  };
}
