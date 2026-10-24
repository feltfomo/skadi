{ lexicon, rootPath, ... }:
{
  den.aspects.helix = lexicon {
    # evilhelix uses helix's config and runtime theme layout
    package = pkgs: pkgs.evil-helix;
    furnish.directories = [
      {
        source = "${rootPath}/configs/helix";
        destination = ".config/helix";
      }
    ];
    theme = {
      id = "helix";
      output = ".config/helix/themes/reactive.toml";
      renderers = {
        noctalia = {
          source = "${rootPath}/configs/helix/reactive.toml";
          sharedWith = [
            "illogical-impulse"
            "serpantinum"
            "end4-pc"
            "dms"
          ];
        };
        caelestia.source = "${rootPath}/configs/helix/caelestia.toml";
      };
    };
  };
}
