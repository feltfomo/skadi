{
  den.aspects.shell.homeManager = { pkgs, ... }: {
    programs.tealdeer.enable = true;

    home.packages = with pkgs; [
      hyperfine
      libnotify
      ripgrep
      procs
      dust
      ouch
      duf
      sd
      xh
      jq
    ];
  };
}
