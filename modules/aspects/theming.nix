_: {
  den.aspects.theming = {
    nixos =
      { pkgs, ... }:
      {
        # Qt theming is owned entirely by the qt-hm aspect (home-manager), which
        # sets platformTheme = "qtct". the old system-level qt block set
        # platformTheme = "qt5ct" here, which disagreed with home-manager; only
        # the qt5ct/qt6ct/kvantum packages stay at the system level.
        environment.systemPackages = with pkgs; [
          libsForQt5.qt5ct
          qt6Packages.qt6ct
          libsForQt5.qtstyleplugin-kvantum
        ];
      };

    homeManager =
      { pkgs, ... }:
      {
        gtk = {
          enable = true;
          colorScheme = "dark";
          iconTheme = {
            name = "Papirus-Dark";
            package = pkgs.papirus-icon-theme;
          };
        };

        programs.btop = {
          enable = true;
          settings = {
            color_theme = "noctalia";
            theme_background = "false";
            true-color = true;
            rounded-corners = true;
            temp_scale = "fahrenheit";
          };
        };

        # cursor theme for gtk, x11/xwayland and wayland (from wiki)
        home.pointerCursor =
          let
            getFrom = url: hash: name: {
              gtk.enable = true;
              x11.enable = true;
              inherit name;
              size = 48;
              package = pkgs.runCommand "moveUp" { } ''
                mkdir -p $out/share/icons
                ln -s ${pkgs.fetchzip { inherit url hash; }} $out/share/icons/${name}
              '';
            };
          in
          getFrom "https://github.com/rose-pine/cursor/releases/download/v1.1.0/BreezeX-RosePine-Linux.tar.xz"
            "sha256-t5xwAPGhuQUfGThedLsmtZEEp1Ljjo3Udhd5Ql3O67c="
            "BreezeX-RosePine-Linux";
      };
  };
}
