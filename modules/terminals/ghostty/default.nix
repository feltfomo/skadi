{
  lexicon,
  ...
}:
{
  den.aspects.ghostty = lexicon {
    package = pkgs: pkgs.ghostty;
    furnish.directories = [
      {
        source = ./config;
        destination = ".config/ghostty";
      }
    ];
    theme =
      { pkgs, ... }:
      let
        reload = pkgs.writeShellApplication {
          name = "ghostty-reload-theme";
          runtimeInputs = with pkgs; [
            procps
            glib
          ];
          text = "exec ${pkgs.python3}/bin/python ${./reload.py}";
        };
      in
      {
        id = "ghostty";
        output = ".config/ghostty/themes/reactive.conf";
        reload = "${reload}/bin/ghostty-reload-theme";
        renderers = {
          noctalia = {
            source = ./config/themes/reactive.conf;
            sharedWith = [
              "illogical-impulse"
              "serpantinum"
              "end4-pc"
              "dms"
            ];
          };
          caelestia = {
            source = ./config/themes/caelestia.conf;
            placedAs = "theme.conf";
          };
        };
      };
  };
}
