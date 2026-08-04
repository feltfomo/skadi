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
      source = "${rootPath}/configs/ghostty/themes/skadi.conf";
      output = ".config/ghostty/themes/skadi.conf";
      renderers = {
        noctalia = { };
        dms = { };
        caelestia = {
          source = "${rootPath}/configs/ghostty/themes/caelestia.conf";
          placedAs = "theme.conf";
        };
      };
    };
  };
}
