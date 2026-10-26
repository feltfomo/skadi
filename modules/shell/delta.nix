{
  den.aspects.shell.homeManager = { pkgs, ... }: {
    home.packages = [ pkgs.delta ];

    programs.git.settings = {
      core.pager = "delta";
      interactive.diffFilter = "delta --color-only";
      delta = {
        navigate = true;
        "line-numbers" = true;
        "side-by-side" = true;
      };
      merge.conflictStyle = "zdiff3";
    };
  };
}
