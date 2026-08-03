{
  program,
  rootPath,
  ...
}:
{
  den.aspects.ghostty = program {
    pkg = pkgs: pkgs.ghostty;
    directories = [
      {
        src = "${rootPath}/configs/ghostty";
        dest = ".config/ghostty";
      }
    ];
    theme.noctalia = {
      id = "ghostty";
      source = "${rootPath}/configs/ghostty/themes/skadi.conf";
      output = ".config/ghostty/themes/skadi.conf";
    };
  };
}
