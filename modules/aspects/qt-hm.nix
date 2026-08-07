{
  den.aspects.qt-hm.homeManager =
    { config, ... }:
    {
      qt = {
        enable = true;
        platformTheme.name = "qtct";

        qt5ctSettings = {
          Appearance = {
            color_scheme_path = "${config.home.homeDirectory}/.config/qt5ct/colors/noctalia.conf";
            custom_palette = true;
            style = "Fusion";
          };
        };

        qt6ctSettings = {
          Appearance = {
            color_scheme_path = "${config.home.homeDirectory}/.config/qt6ct/colors/noctalia.conf";
            custom_palette = true;
            style = "Fusion";
          };
        };
      };
    };
}
