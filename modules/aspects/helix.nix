{ program, rootPath, ... }:
{
  den.aspects.helix = program {
    # evilhelix uses helix's config and runtime theme layout
    pkg = pkgs: pkgs.evil-helix;
    directories = [
      {
        src = "${rootPath}/configs/helix";
        dest = ".config/helix";
      }
    ];
    theme = {
      id = "helix";
      output = ".config/helix/themes/reactive.toml";
      renderers = {
        noctalia = {
          source = "${rootPath}/configs/helix/reactive.toml";
          sharedWith = [
            "dms"
            "illogical-impulse"
            "end4-pc"
          ];
        };
        caelestia.source = "${rootPath}/configs/helix/caelestia.toml";
      };
    };
  };
}
