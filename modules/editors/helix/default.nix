{ lexicon, ... }:
{
  den.aspects.helix = lexicon {
    # evilhelix uses helix's config and runtime theme layout
    package = pkgs: pkgs.evil-helix;
    furnish.directories = [
      {
        source = ./config;
        destination = ".config/helix";
      }
    ];
    theme = {
      id = "helix";
      output = ".config/helix/themes/reactive.toml";
      renderers = {
        noctalia = {
          source = ./config/reactive.toml;
          sharedWith = [
            "illogical-impulse"
            "serpantinum"
            "end4-pc"
            "dms"
          ];
        };
        caelestia.source = ./config/caelestia.toml;
      };
    };
  };
}
