# publishes the user's live palette and wallpaper for the boot-theme service, which renders them
# onto the esp. only noctalia's templates can name the wallpaper, through `{{ image }}`. other
# shells publish nothing, and the boot keeps the fallback theme.
{
  config,
  den,
  lexicon,
  ...
}:
let
  # success and warning aren't material roles, so noctalia has no token for them.
  roles = builtins.filter (role: role != "success" && role != "warning") (
    builtins.attrNames config.skadi.fallbackPalette
  );
  template = builtins.toJSON (
    {
      wallpaper = "{{ image }}";
    }
    // builtins.listToAttrs (
      map (role: {
        name = role;
        value = "{{ colors.${role}.default.hex }}";
      }) roles
    )
  );
in
{
  den.aspects.boot-theme-live.includes = [
    den.aspects.boot-theme-palette
    ({ user, ... }: { nixos.skadi.bootTheme.publisher = user.userName; })
  ];

  den.aspects.boot-theme-palette = lexicon {
    theme = {
      id = "boot";
      renderers.noctalia = {
        source = builtins.toFile "boot.json" template;
        placedAs = "boot.json";
        output = ".local/state/skadi/boot.json";
      };
    };
  };
}
