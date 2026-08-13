{ program, rootPath, ... }:
{
  den.aspects.qt-hm = program {
    imports = [
      (
        { config, ... }:
        {
          qt = {
            enable = true;
            platformTheme.name = "qtct";

            qt5ctSettings.Appearance = {
              color_scheme_path = "${config.home.homeDirectory}/.config/qt5ct/colors/reactive.conf";
              custom_palette = true;
              style = "Fusion";
            };

            qt6ctSettings.Appearance = {
              color_scheme_path = "${config.home.homeDirectory}/.config/qt6ct/colors/reactive.conf";
              custom_palette = true;
              style = "Fusion";
            };
          };
        }
      )
    ];

    theme = {
      id = "qt";
      templates = [
        {
          subId = "qt5ct";
          output = ".config/qt5ct/colors/reactive.conf";
          placedAs = "qt5ct.conf";
          renderers = {
            noctalia = {
              source = "${rootPath}/configs/qt/reactive.conf";
              sharedWith = [
                "dms"
                "illogical-impulse"
                "end4-pc"
              ];
            };
            caelestia.source = "${rootPath}/configs/qt/caelestia.conf";
          };
        }
        {
          subId = "qt6ct";
          output = ".config/qt6ct/colors/reactive.conf";
          placedAs = "qt6ct.conf";
          renderers = {
            noctalia = {
              source = "${rootPath}/configs/qt/reactive.conf";
              sharedWith = [
                "dms"
                "illogical-impulse"
                "end4-pc"
              ];
            };
            caelestia.source = "${rootPath}/configs/qt/caelestia.conf";
          };
        }
      ];
    };
  };
}
