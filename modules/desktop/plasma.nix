{
  den.aspects.plasma.nixos =
    { pkgs, ... }:
    {
      services.desktopManager.plasma6 = {
        enable = true;
        enableQt5Integration = false;
      };
      services.flatpak.enable = true;
      programs.kde-pim.enable = false;

      environment.plasma6.excludePackages = with pkgs.kdePackages; [
        plasma-workspace-wallpapers
        plasma-browser-integration
        dolphin-plugins
        baloo-widgets
        khelpcenter
        ktexteditor
        spectacle
        gwenview
        konsole
        okular
        elisa
        kate
        krdp
        ark
      ];
    };
}
