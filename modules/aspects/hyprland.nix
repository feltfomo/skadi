{
  inputs,
  rootPath,
  program,
  ...
}:
let
  # keep audio-playing windows opaque while inactive.
  audioOpacityService =
    { pkgs, ... }:
    let
      hyprctlPkg = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
      # body in scripts/audio-opacity.sh; writeShellApplication adds the shebang + PATH.
      audio-opacity = pkgs.writeShellApplication {
        name = "audio-opacity";
        runtimeInputs = [
          hyprctlPkg
          pkgs.pulseaudio
          pkgs.jq
          pkgs.gawk
          pkgs.procps
          pkgs.coreutils
        ];
        text = builtins.readFile ../../scripts/audio-opacity.sh;
      };
    in
    {
      systemd.user.services.audio-opacity = {
        Unit = {
          Description = "Undim windows that are playing audio while inactive";
          After = [ "graphical-session.target" ];
          PartOf = [ "graphical-session.target" ];
        };
        Service = {
          ExecStart = "${audio-opacity}/bin/audio-opacity";
          Restart = "always";
          RestartSec = 2;
        };
      };
    };
in
{
  # nixos = compositor, homeManager = daemon, hjem = config files. owned by
  # khion + lumi; vm stays excluded so the headless installer-test VM never
  # pulls the compositor closure.
  den.aspects.hyprland = program {
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
        programs.hyprland = {
          enable = true;
          package = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
          portalPackage =
            inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland;
        };
        services.flatpak.enable = true;

        # gnome and hyprland each ship a ScreenCast portal
        # (xdg-desktop-portal-gnome vs -hyprland). with no routing config,
        # xdg-desktop-portal can hand a hyprland-session ScreenCast to the gnome
        # backend, which only works inside gnome shell -> discord/equibop
        # screenshare comes up black or lists no windows. pin the hyprland
        # session (XDG_CURRENT_DESKTOP=Hyprland -> hyprland-portals.conf) to the
        # hyprland backend; keep FileChooser on gtk for native file dialogs.
        xdg.portal = {
          extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
          config.hyprland = {
            default = [
              "hyprland"
              "gtk"
            ];
            "org.freedesktop.impl.portal.ScreenCast" = [ "hyprland" ];
            "org.freedesktop.impl.portal.Screenshot" = [ "hyprland" ];
            "org.freedesktop.impl.portal.FileChooser" = [ "gtk" ];
          };
        };
      }
    ];
    imports = [ audioOpacityService ];
    files = [
      {
        dest = ".config/hypr/hyprland.lua";
        src = "${rootPath}/configs/hypr/hyprland.lua";
      }
      {
        dest = ".config/hypr/autostart.lua";
        src = "${rootPath}/configs/hypr/autostart.lua";
      }
      {
        dest = ".config/hypr/binds.lua";
        src = "${rootPath}/configs/hypr/binds.lua";
      }
      {
        dest = ".config/hypr/decoration.lua";
        src = "${rootPath}/configs/hypr/decoration.lua";
      }
      {
        dest = ".config/hypr/environment.lua";
        src = "${rootPath}/configs/hypr/environment.lua";
      }
      {
        dest = ".config/hypr/globals.lua";
        src = "${rootPath}/configs/hypr/globals.lua";
      }
      {
        dest = ".config/hypr/monitor.lua";
        src = "${rootPath}/configs/hypr/monitor.lua";
      }
      {
        dest = ".config/hypr/hl.meta.lua";
        src = "${rootPath}/configs/hypr/hl.meta.lua";
      }
      {
        dest = ".config/hypr/helpers/workspace.lua";
        src = "${rootPath}/configs/hypr/helpers/workspace.lua";
      }
    ];
    theme.noctalia = {
      id = "hyprland";
      source = "${rootPath}/configs/hypr/colors.lua";
      output = ".config/hypr/colors.lua";
    };
  };
}
