{ config, lexicon, ... }:
{
  den.aspects.cava = lexicon {
    package = pkgs: pkgs.cava;
    furnish.directories = [
      {
        source = ./config;
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
    theme = { pkgs, ... }: {
      id = "cava";
      output = ".config/cava/themes/reactive";
      reload = "${pkgs.procps}/bin/pkill -USR1 -x cava || true";
      renderers = {
        noctalia = {
          source = ./config/reactive.ini;
          sharedWith = config.skadi.theme.noctaliaCompatibleRenderers;
        };
        caelestia.source = ./config/caelestia.ini;
      };
    };
  };
}
