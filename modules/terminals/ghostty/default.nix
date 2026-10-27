{
  config,
  lexicon,
  ...
}:
{
  den.aspects.ghostty = lexicon {
    package = pkgs: pkgs.ghostty;
    furnish = {
      users = [ "feltfomo" ];
      directories = [
        {
          source = ./config;
          destination = ".config/ghostty";
        }
      ];
    };
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
        users = [ "feltfomo" ];
        id = "ghostty";
        output = ".config/ghostty/themes/reactive.conf";
        reload = "${reload}/bin/ghostty-reload-theme";
        renderers = {
          noctalia = {
            source = ./config/themes/reactive.conf;
            sharedWith = config.skadi.theme.noctaliaCompatibleRenderers;
          };
          caelestia = {
            source = ./config/themes/caelestia.conf;
            placedAs = "theme.conf";
          };
        };
      };
  };
}
