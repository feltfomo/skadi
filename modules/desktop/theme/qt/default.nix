{ lexicon, ... }:
{
  skadi.packages.skadi-qt-theme = ./_package.nix;

  den.aspects.qt-hm = lexicon {
    homeManager.imports = [
      (
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          theme = pkgs.skadi-qt-theme;
          publish = "${theme}/bin/skadi-qt-theme --palette ${lib.escapeShellArg "${config.xdg.configHome}/qt-theme/palette.json"} --config-home ${lib.escapeShellArg config.xdg.configHome} --data-home ${lib.escapeShellArg config.xdg.dataHome}";
          appearance = {
            color_scheme_path = "${config.xdg.configHome}/qt5ct/colors/reactive.conf";
            custom_palette = true;
            icon_theme = config.gtk.iconTheme.name;
            style = "kvantum";
          };
          fonts = {
            general = ''"Maple Mono NF,10,-1,5,50,0,0,0,0,0,0,0,0,0,0,1"'';
            fixed = ''"Maple Mono NF,10,-1,5,50,0,0,0,0,0,0,0,0,0,0,1"'';
          };
        in
        {
          home.packages = [ theme ];
          home.activation.skadiQtTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            run ${publish}
          '';

          qt = {
            enable = true;
            platformTheme.name = "qtct";
            style.name = "kvantum";
            kvantum = {
              enable = true;
              settings.General.theme = "Skadi";
            };

            qt5ctSettings = {
              Appearance = appearance;
              Fonts = fonts;
            };
            qt6ctSettings = {
              Appearance = appearance // {
                color_scheme_path = "${config.xdg.configHome}/qt6ct/colors/reactive.conf";
              };
              Fonts = fonts;
            };
          };
        }
      )
    ];

    theme =
      { pkgs, ... }:
      let
        theme = pkgs.skadi-qt-theme;
      in
      {
        id = "qt";
        output = ".config/qt-theme/palette.json";
        reload = ''${theme}/bin/skadi-qt-theme --palette "$HOME/.config/qt-theme/palette.json" --config-home "$HOME/.config" --data-home "$HOME/.local/share"'';
        template = ./config/reactive.json;
        placedAs = "qt.json";
      };
  };
}
