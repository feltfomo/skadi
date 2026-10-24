{
  lexicon,
  rootPath,
  ...
}:
{
  den.aspects.ghostty = lexicon {
    package = pkgs: pkgs.ghostty;
    furnish.directories = [
      {
        source = "${rootPath}/configs/ghostty";
        destination = ".config/ghostty";
      }
    ];
    theme = {
      id = "ghostty";
      output = ".config/ghostty/themes/reactive.conf";
      reload = "pkill -USR2 -f '/bin/[g]hostty --gtk-single-instance=true'";
      renderers = {
        noctalia = {
          source = "${rootPath}/configs/ghostty/themes/reactive.conf";
          sharedWith = [
            "illogical-impulse"
            "serpantinum"
            "end4-pc"
            "dms"
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
