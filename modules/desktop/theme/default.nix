{
  den.aspects.theming = {
    nixos =
      { pkgs, ... }:
      {
        # the overlay must leave gtk4 stock: overriding it rebuilds every gtk 4 consumer from source.
        nixpkgs.overlays = [ (import ./hot-reload/_package/overlay.nix) ];
        # both toolkits find the reload module through GTK_PATH: gtk 4 scans its immodules directory,
        # and gtk 3 loads GTK_MODULES by name. gtk 3 ignores gtk-modules from settings.ini at startup,
        # so the session variable is the only startup hook that works on wayland.
        environment.systemPackages = [ pkgs.skadi-gtk-reload ];
        environment.sessionVariables.GTK_MODULES = [ "skadi-palette-reload" ];
        # system desktop entries launch outside home manager's environment.
        # qt-hm selects kvantum and publishes the matching qtct palette.
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
          colorScheme = null;
          theme = {
            name = "Skadi";
            package = pkgs.skadi-gtk-theme;
          };
          # the palette hook owns gtk4 user css and needs a writable file.
          gtk4.theme = null;
          iconTheme = {
            name = "Papirus-Dark";
            package = pkgs.papirus-icon-theme;
          };
        };

        dconf.settings."org/gnome/desktop/interface".gtk-theme = config.gtk.theme.name;

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
