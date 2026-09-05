{ program, rootPath, ... }:
{
  den.aspects.cava = program {
    pkg = pkgs: pkgs.cava;
    directories = [
      {
        src = "${rootPath}/configs/cava";
        dest = ".config/cava";
      }
    ];
    theme = {
      id = "cava";
      output = ".config/cava/themes/reactive";
      reload = ''nu "$HOME/.config/cava/apply.nu"'';
      renderers = {
        noctalia = {
          source = "${rootPath}/configs/cava/reactive.ini";
          sharedWith = [
            "dms"
            "illogical-impulse"
            "end4-pc"
          ];
        };
        caelestia.source = "${rootPath}/configs/cava/caelestia.ini";
      };
    };
  };
}
