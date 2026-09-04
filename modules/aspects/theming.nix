{
  den.aspects.theming = {
    nixos = {
      # system desktop entries launch outside home manager's environment.
      # qt-hm selects fusion so qtct can apply noctalia's generated palette.
      qt = {
        enable = true;
        platformTheme = "qt5ct";
      };
    };

    homeManager =
      { pkgs, config, ... }:
      {
        gtk = {
          enable = true;
          colorScheme = "dark";
          gtk4.theme = config.gtk.theme;
          iconTheme = {
            name = "Papirus-Dark";
            package = pkgs.papirus-icon-theme;
          };
        };

        home.packages = [ pkgs.adw-gtk3 ];
        dconf.settings."org/gnome/desktop/interface".gtk-theme = "adw-gtk3-dark";

        programs.btop = {
          enable = true;
          settings = {
            color_theme = "reactive";
            theme_background = "false";
            true-color = true;
            rounded-corners = true;
            temp_scale = "fahrenheit";
          };
        };

        # cursor theme for gtk + x11/xwayland/wayland
        home.pointerCursor =
          let
            getFrom = url: hash: name: {
              enable = true;
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
