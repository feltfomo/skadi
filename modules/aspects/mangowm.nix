{
  inputs,
  rootPath,
  program,
  ...
}:
{
  # nixos = compositor (programs.mango from the mango flake), hjem = config
  # files. owned by khion + lumi; vm stays excluded so the headless
  # installer-test VM never pulls the compositor closure. sits alongside
  # hyprland -- both compositors install, the display manager lists both
  # sessions, you pick one per login.
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
        # wlr portal for screen sharing under mango. hyprland's portal stays
        # wired by its own aspect; mango-portals.conf routes ScreenCast to wlr
        # only when a mango session is running.
        environment.systemPackages = [ pkgs.xdg-desktop-portal-wlr ];
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
    templates = [
      {
        name = "colors.conf";
        templateFile = "${rootPath}/configs/mango/colors.conf.tpl";
        subdir = "mango/";
      }
    ];
    noctaliaConfig = {
      _fileName = "mango";
      theme.templates.user.mango = {
        input_path = "~/.config/noctalia/templates/mango/colors.conf";
        output_path = "~/.config/mango/colors.conf";
        # reload mango after rendering so the new palette applies live, same
        # pattern as kitty's post_hook=pkill -SIGUSR1 kitty.
        post_hook = "mmsg -d reload_config";
      };
    };
  };
}
