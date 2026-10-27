{
  config,
  inputs,
  lexicon,
  ...
}:
{
  den.aspects.superfile = lexicon {
    homeManager.programs.superfile = {
      enable = true;
      settings = import ./_settings.nix;
    };
    theme =
      { pkgs, ... }:
      let
        toml = inputs.lexicon.lib.toml { inherit pkgs; };
        themes = import ./_themes.nix;
      in
      {
        id = "superfile";
        output = ".config/superfile/theme/reactive.toml";
        renderers = {
          noctalia = {
            source = toString (toml.generate "superfile-reactive.toml" themes.reactive);
            placedAs = "reactive.toml";
            sharedWith = config.skadi.theme.noctaliaCompatibleRenderers;
          };
          caelestia = {
            source = toString (toml.generate "superfile-caelestia.toml" themes.caelestia);
            placedAs = "caelestia.toml";
          };
        };
      };
  };
}
