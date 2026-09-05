{
  den.aspects.shell.homeManager = { pkgs, ... }: {
    programs.tealdeer.enable = true;

    home.packages = with pkgs; [
      fd
      eza
      ripgrep
      dust
      duf
      procs
      sd
      hyperfine
      xh
      ouch
      jq
      libnotify
    ];
  };
}
