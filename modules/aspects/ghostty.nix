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
    theme = {
      id = "ghostty";
      output = ".config/ghostty/themes/skadi.conf";
      reload = "for pid in $(pgrep -f '/bin/[g]hostty --gtk-single-instance=true'); do kill -SIGUSR2 \"$pid\"; done";
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
