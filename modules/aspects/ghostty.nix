{
  program,
  rootPath,
  ...
}:
let
  skadiTheme = {
    source = "${rootPath}/configs/ghostty/themes/skadi.conf";
    output = ".config/ghostty/themes/skadi.conf";
  };
in
{
  den.aspects.ghostty = program {
    pkg = pkgs: pkgs.ghostty;
    directories = [
      {
        src = "${rootPath}/configs/ghostty";
        dest = ".config/ghostty";
      }
    ];
    theme = {
      noctalia = {
        id = "ghostty";
      }
      // skadiTheme;
      dms = {
        id = "ghostty";
      }
      // skadiTheme;
    };
  };
}
