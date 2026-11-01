{ lexicon, ... }:
{
  den.aspects.arx-theme = lexicon {
    theme = {
      id = "arx";
      output = ".config/arx/theme.toml";
      template = ./config/theme.toml;
    };
  };
}
