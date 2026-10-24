{ lexicon, rootPath, ... }:
{
  den.aspects.cava = lexicon {
    package = pkgs: pkgs.cava;
    furnish.directories = [
      {
        source = "${rootPath}/configs/cava";
        destination = ".config/cava";
        files = [
          {
            names = [ "config" ];
            representation = "writable";
            onConflict = "source-wins";
          }
        ];
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
            "illogical-impulse"
            "serpantinum"
            "end4-pc"
            "dms"
          ];
        };
        caelestia.source = "${rootPath}/configs/cava/caelestia.ini";
      };
    };
  };
}
