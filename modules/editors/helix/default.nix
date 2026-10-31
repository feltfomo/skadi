{
  inputs,
  lexicon,
  ...
}:
{
  den.aspects.helix = lexicon {
    # evilhelix uses helix's config and runtime theme layout
    package = pkgs: pkgs.evil-helix;
    furnish.files = { pkgs, ... }: [
      {
        source = (inputs.lexicon.lib.toml { inherit pkgs; }).generate "helix-config.toml" (
          import ./_settings.nix
        );
        destination = ".config/helix/config.toml";
      }
    ];
    theme =
      { pkgs, ... }:
      let
        toml = inputs.lexicon.lib.toml { inherit pkgs; };
        theme = import ./_theme.nix;
        palette = import ./_palettes.nix;
      in
      {
        id = "helix";
        output = ".config/helix/themes/reactive.toml";
        template = toml.render (theme palette);
        placedAs = "reactive.toml";
      };
  };
}
