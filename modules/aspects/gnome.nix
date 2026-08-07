{
  den.aspects.gnome = {
    nixos =
      { pkgs, ... }:
      {
        services = {
          displayManager.gdm.enable = true;
          desktopManager.gnome.enable = true;
          # flatpak lives with the desktop that provides its xdg portal (gnome
          # ships its own), not in base -- a lean base install has no app-store.
          flatpak.enable = true;
        };

        environment.gnome.excludePackages = with pkgs; [
          atomix
          cheese
          epiphany
          evince
          geary
          gedit
          gnome-characters
          gnome-music
          gnome-photos
          gnome-terminal
          gnome-tour
          hitori
          iagno
          tali
          totem
        ];
      };

    homeManager =
      { pkgs, ... }:
      {
        dconf = {
          enable = true;
          settings."org/gnome/shell" = {
            disable-user-extensions = false;
            enabled-extensions = with pkgs.gnomeExtensions; [
              blur-my-shell.extensionUuid
              gsconnect.extensionUuid
            ];
          };
          settings."org/gnome/desktop/interface".color-scheme = "prefer-dark";
        };
      };
  };
}
