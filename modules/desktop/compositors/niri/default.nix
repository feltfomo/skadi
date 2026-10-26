{
  inputs,
  lexicon,
  ...
}:
{
  flake-file.inputs.niri = {
    url = "github:epireyn/niri-flake";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  den.aspects.niri = lexicon {
    hosts = [
      "khion"
      "lumi"
    ];
    nixos = { pkgs, ... }: [
      {
        value = {
          imports = [ inputs.niri.nixosModules.niri ];
          nixpkgs.overlays = [ inputs.niri.overlays.niri ];
          programs.niri = {
            enable = true;
            package = pkgs.niri-unstable;
          };
          environment.systemPackages = [ pkgs.xwayland-satellite-unstable ];
          services.flatpak.enable = true;

          xdg.portal = {
            enable = true;
            extraPortals = with pkgs; [
              xdg-desktop-portal-gnome
              xdg-desktop-portal-gtk
            ];
            config.niri = {
              default = [
                "gnome"
                "gtk"
              ];
              "org.freedesktop.impl.portal.FileChooser" = [ "gtk" ];
              "org.freedesktop.impl.portal.ScreenCast" = [ "gnome" ];
              "org.freedesktop.impl.portal.Screenshot" = [ "gnome" ];
              "org.freedesktop.impl.portal.Access" = [ "gtk" ];
              "org.freedesktop.impl.portal.Notification" = [ "gtk" ];
            };
          };
        };
      }
    ];
    furnish.directories = [
      {
        source = ./config;
        destination = ".config/niri";
      }
    ];
    theme = {
      id = "niri";
      renderers.dms = {
        source = ./config/colors.kdl;
        output = ".config/niri/colors.kdl";
      };
    };
  };
}
