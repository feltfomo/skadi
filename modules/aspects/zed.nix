{ program, rootPath, ... }:
{
  den.aspects.zed = program {
    pkg = pkgs: pkgs.zed-editor;
    theme = {
      id = "zed";
      renderers = {
        noctalia = {
          source = "${rootPath}/configs/zed/themes/skadi.json";
          output = ".config/zed/themes/skadi.json";
          reload = "zed --unstable-features theme-reload";
        };
        dms = {
          source = "${rootPath}/configs/zed/themes/skadi.json";
          output = ".config/zed/themes/skadi.json";
          reload = "zed --unstable-features theme-reload";
        };
        illogical-impulse = {
          source = "${rootPath}/configs/zed/themes/skadi.json";
          output = ".config/zed/themes/skadi.json";
          reload = "zed --unstable-features theme-reload";
        };
        end4-pc = {
          source = "${rootPath}/configs/zed/themes/skadi.json";
          output = ".config/zed/themes/skadi.json";
          reload = "zed --unstable-features theme-reload";
        };
        caelestia = {
          source = "${rootPath}/configs/zed/themes/caelestia.json";
          output = ".config/zed/themes/skadi.json";
          placedAs = "theme.json";
          reload = "zed --unstable-features theme-reload";
        };
      };
    };
  };
}
