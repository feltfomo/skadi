{ ... }:
{
  flake.modules.nixos.qt-hm =
    { ... }:
    {
      home-manager.users.feltfomo =
        { ... }:
        {
          qt = {
            enable = true;
            kvantum = {
              enable = true;
              settings = {
                General = {
                  theme = "KvGnomeDark";
                };
              };
            };

            platformTheme.name = "qtct";

            qt5ctSettings = {
              Appearance = {
                color_scheme_path = "/home/YOUR_USER/.config/qt5ct/colors/noctalia.conf";
                custom_palette = true;
                style = "kvantum";
              };
            };

            qt6ctSettings = {
              Appearance = {
                color_scheme_path = "/home/YOUR_USER/.config/qt6ct/colors/noctalia.conf";
                custom_palette = true;
                style = "kvantum";
              };
            };
          };
        };
    };
}
