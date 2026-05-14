{ ... }:
{
  flake.nixosModules.gnome =
    { pkgs, ... }:
    {
      # enable gnome and gdm
      services = {
        displayManager.gdm.enable = true;
        desktopManager.gnome.enable = true;
      };

      # exclude gnome apps that are not needed
      environment.gnome.excludePackages = (
        with pkgs;
        [
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
        ]
      );

      # configure gnome settings for feltfomo
      home-manager.users.feltfomo =
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
