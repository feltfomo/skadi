{
  inputs,
  rootPath,
  program,
  ...
}:
{
  flake-file.inputs.mango = {
    url = "github:mangowm/mango";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  # vm excluded. the installer-test VM doesn't need a compositor
  # closure. coexists with hyprland, not a replacement.
  den.aspects.mangowm = program {
    hosts = [
      "khion"
      "lumi"
    ];
    nixos = { pkgs, ... }: [
      {
        imports = [ inputs.mango.nixosModules.mango ];
        programs.mango = {
          enable = true;
          package = inputs.mango.packages.${pkgs.stdenv.hostPlatform.system}.default;
        };
        # wlr must be registered as a portal, not only installed as a package.
        # mango-portals.conf routes screencast to wlr and file dialogs to gtk.
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
    directories = [
      {
        src = "${rootPath}/configs/mango";
        dest = ".config/mango";
        exclude = [ "portal.conf" ];
        files = [
          {
            names = [
              "environment-khion.conf"
              "monitors-khion.conf"
            ];
            hosts = [ "khion" ];
          }
          {
            names = [ "monitors-lumi.conf" ];
            hosts = [ "lumi" ];
          }
        ];
      }
    ];
    files = [
      {
        dest = ".config/xdg-desktop-portal/mango-portals.conf";
        src = "${rootPath}/configs/mango/portal.conf";
      }
    ];
    theme = {
      id = "mango";
      renderers.noctalia = {
        source = "${rootPath}/configs/mango/colors.conf";
        output = ".config/mango/colors.conf";
        # noctalia starts before mango exports its ipc socket, so discover it here
        reload = ''runtime_dir="$XDG_RUNTIME_DIR"; [ -n "$runtime_dir" ] || runtime_dir="/run/user/$(id -u)"; socket="$(find "$runtime_dir" -maxdepth 1 -type s -name 'mango-*.sock' -print -quit)"; if [ -n "$socket" ]; then MANGO_INSTANCE_SIGNATURE="$socket" mmsg dispatch reload_config; fi'';
      };
    };
  };
}
