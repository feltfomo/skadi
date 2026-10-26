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
    theme = {
      id = "cava";
      output = ".config/cava/themes/reactive";
      reload = ''nu "$HOME/.config/cava/apply.nu"'';
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
