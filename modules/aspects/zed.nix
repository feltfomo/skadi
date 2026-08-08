{ program, rootPath, ... }:
{
  den.aspects.zed = program {
    pkg = pkgs: pkgs.zed-editor;
    theme = {
      id = "zed";
      output = ".config/zed/themes/skadi.json";
      reload = "zed --unstable-features theme-reload";
      renderers = {
        noctalia = {
          source = "${rootPath}/configs/zed/themes/skadi.json";
          sharedWith = [
            "dms"
            "illogical-impulse"
            "end4-pc"
          ];
        };
        caelestia = {
          source = "${rootPath}/configs/zed/themes/caelestia.json";
          placedAs = "theme.json";
        };
      };
    };
  };
}
