{ den, ... }:
{
  den.aspects.gnome = {
    includes = [ den.aspects.gdm ];

    nixos =
      { pkgs, ... }:
      {
        services = {
          desktopManager.gnome.enable = true;
          # enable flatpak here because gnome supplies its xdg portal.
          flatpak.enable = true;
        };

        environment.gnome.excludePackages = with pkgs; [
          gnome-characters
          gnome-terminal
          gnome-music
          gnome-tour
          epiphany
          atomix
          cheese
          evince
          hitori
          geary
          gedit
          iagno
          totem
          tali
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
