{
  inputs,
  rootPath,
  program,
  ...
}:
{
  # vm excluded. the installer-test VM doesn't need a compositor
  # closure. coexists with hyprland, not a replacement.
  den.aspects.mangowm = program {
    hosts = [
      "khion"
      "lumi"
    ];
    nixos = { pkgs, ... }: [
      {
        hosts = [
          "khion"
          "lumi"
        ];
        imports = [ inputs.mango.nixosModules.mango ];
        programs.mango = {
          enable = true;
          package = inputs.mango.packages.${pkgs.stdenv.hostPlatform.system}.default;
        };
        # wlr screencast portal for mango sessions (hyprland keeps its own).
        # a plain systemPackages install was the bug. nixos only exposes a
        # backend's .portal file to the wrapped xdg-desktop-portal service when
        # it's in xdg.portal.extraPortals, so the router had no ScreenCast impl
        # under mango and the share picker never appeared. wlr.enable registers
        # it and writes the xdph config; slurp is the output chooser. routing to
        # wlr already lives in the linked mango-portals.conf, and gtk covers the
        # FileChooser/OpenURI portals in the session.
        xdg.portal = {
          enable = true;
          wlr.enable = true;
          wlr.settings.screencast = {
            chooser_type = "simple";
            chooser_cmd = "${pkgs.slurp}/bin/slurp -f %o -or";
            max_fps = 60;
          };
          extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
        };
      }
    ];
    files = [
      {
        dest = ".config/mango/config.conf";
        src = "${rootPath}/configs/mango/config.conf";
      }
      {
        dest = ".config/mango/settings.conf";
        src = "${rootPath}/configs/mango/settings.conf";
      }
      {
        dest = ".config/mango/environment.conf";
        src = "${rootPath}/configs/mango/environment.conf";
      }
      {
        dest = ".config/mango/environment-khion.conf";
        src = "${rootPath}/configs/mango/environment-khion.conf";
        hosts = [ "khion" ];
      }
      {
        dest = ".config/mango/monitors-khion.conf";
        src = "${rootPath}/configs/mango/monitors-khion.conf";
        hosts = [ "khion" ];
      }
      {
        dest = ".config/mango/monitors-lumi.conf";
        src = "${rootPath}/configs/mango/monitors-lumi.conf";
        hosts = [ "lumi" ];
      }
      {
        dest = ".config/mango/autostart.conf";
        src = "${rootPath}/configs/mango/autostart.conf";
      }
      {
        dest = ".config/mango/binds.conf";
        src = "${rootPath}/configs/mango/binds.conf";
      }
      {
        dest = ".config/xdg-desktop-portal/mango-portals.conf";
        src = "${rootPath}/configs/mango/portal.conf";
      }
    ];
    theme.noctalia = {
      id = "mango";
      source = "${rootPath}/configs/mango/colors.conf";
      output = ".config/mango/colors.conf";
      # reload so the new palette applies live (kitty does the same
      # with pkill -SIGUSR1).
      reload = "mmsg -d reload_config";
    };
  };
}
