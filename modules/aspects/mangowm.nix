{
  inputs,
  rootPath,
  program,
  ...
}:
{
  # vm excluded -- the installer-test VM doesn't need a compositor
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
        # wlr portal for mango sessions. hyprland's stays on its own aspect.
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
        # reload so the new palette applies live (kitty does the same
        # with pkill -SIGUSR1).
        post_hook = "mmsg -d reload_config";
      };
    };
  };
}
