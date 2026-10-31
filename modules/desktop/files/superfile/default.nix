{
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
        palette = import ./_themes.nix;
      in
      {
        id = "superfile";
        output = ".config/superfile/theme/reactive.toml";
        template = toml.render palette;
        placedAs = "reactive.toml";
      };
  };
}
