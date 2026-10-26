{ config, lexicon, ... }:
{
  den.aspects.superfile = lexicon {
    homeManager.programs.superfile = {
      enable = true;
      settings = builtins.fromTOML (builtins.readFile ./config/config.toml);
    };
    theme = {
      id = "superfile";
      output = ".config/superfile/theme/reactive.toml";
      renderers = {
        noctalia = {
          source = ./config/reactive.toml;
          sharedWith = config.skadi.theme.noctaliaCompatibleRenderers;
        };
        caelestia.source = ./config/caelestia.toml;
      };
    };
  };
}
