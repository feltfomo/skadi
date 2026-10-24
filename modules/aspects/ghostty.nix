{
  lexicon,
  rootPath,
  ...
}:
{
  den.aspects.ghostty = lexicon {
    package = pkgs: pkgs.ghostty;
    furnish.directories = [
      {
        source = "${rootPath}/configs/ghostty";
        destination = ".config/ghostty";
      }
    ];
    theme =
      { pkgs, ... }:
      let
        reload = pkgs.writeShellApplication {
          name = "ghostty-reload-theme";
          runtimeInputs = [
            pkgs.procps
            pkgs.glib
          ];
          text = "exec ${pkgs.python3}/bin/python ${rootPath}/scripts/ghostty-reload.py";
        };
      in
      {
        id = "ghostty";
        output = ".config/ghostty/themes/reactive.conf";
        reload = "${reload}/bin/ghostty-reload-theme";
        renderers = {
          noctalia = {
            source = "${rootPath}/configs/ghostty/themes/reactive.conf";
            sharedWith = [
              "illogical-impulse"
              "serpantinum"
              "end4-pc"
              "dms"
            ];
          };
          caelestia = {
            source = "${rootPath}/configs/ghostty/themes/caelestia.conf";
            placedAs = "theme.conf";
          };
        };
      };
  };
}
