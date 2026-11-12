# publishes the user's live palette and wallpaper for the boot-theme service, which renders them
# onto the esp. the palette is a portable template, so lexicon derives every role the fallback
# palette has, success and warning included. only noctalia can name the wallpaper, through its own
# `{{ image }}`, so the template is noctalia's alone. other shells publish nothing, and the boot
# keeps the fallback theme.
{
  config,
  den,
  lexicon,
  lib,
  ...
}:
let
  template = builtins.toJSON (
    lib.mapAttrs (role: _: "{{ ${lib.toCamelCase role} }}") config.skadi.fallbackPalette
  );
in
{
  den.aspects.boot-theme-live.includes = [
    den.aspects.boot-theme-palette
    ({ user, ... }: { nixos.skadi.bootTheme.publisher = user.userName; })
  ];

  den.aspects.boot-theme-palette = lexicon {
    theme =
      { pkgs, ... }:
      {
        id = "boot";
        renderers.noctalia = {
          inherit template;
          placedAs = "boot.json";
          output = ".local/state/skadi/boot.json";
          # lexicon rejects shell-native tokens in a portable template, so the wallpaper goes in after
          # it compiles.
          transform =
            compiled:
            pkgs.runCommand "boot.json" { nativeBuildInputs = [ pkgs.jq ]; } ''
              jq '. + { wallpaper: "{{ image }}" }' ${compiled} > "$out"
            '';
        };
      };
  };
}
