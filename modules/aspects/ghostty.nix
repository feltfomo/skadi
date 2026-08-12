{
  program,
  rootPath,
  ...
}: {
  den.aspects.ghostty = program {
    pkg = pkgs: pkgs.ghostty;
    directories = [
      {
        src = "${rootPath}/configs/ghostty";
        dest = ".config/ghostty";
      }
    ];
    theme = {
      id = "ghostty";
      output = ".config/ghostty/themes/skadi.conf";
      reload = "pkill -USR2 -f '/bin/[g]hostty --gtk-single-instance=true'";
      renderers = {
        noctalia = {
          source = "${rootPath}/configs/ghostty/themes/skadi.conf";
          sharedWith = [
            "dms"
            "illogical-impulse"
            "end4-pc"
          ];
        };
        caelestia = {
          source = "${rootPath}/configs/ghostty/themes/caelestia.conf";
          placedAs = "theme.conf";
        };
      };
    };
  };
}
