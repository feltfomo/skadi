{ lexicon, rootPath, ... }:
{
  den.aspects.superfile = lexicon {
    homeManager.programs.superfile = {
      enable = true;
      settings = builtins.fromTOML (builtins.readFile ../../configs/superfile/config.toml);
    };
    theme = {
      id = "superfile";
      output = ".config/superfile/theme/reactive.toml";
      renderers = {
        noctalia = {
          source = "${rootPath}/configs/superfile/reactive.toml";
          sharedWith = [
            "illogical-impulse"
            "serpantinum"
            "end4-pc"
            "dms"
          ];
        };
        caelestia.source = "${rootPath}/configs/superfile/caelestia.toml";
      };
    };
  };
}
