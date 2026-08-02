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
  # nixos owns the compositor and daemon while furnish owns config files.
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
    directories = [
      {
        src = "${rootPath}/configs/hypr";
        dest = ".config/hypr";
        exclude = [ ".luarc.json" ];
      }
    ];
    theme.noctalia = {
      id = "hyprland";
      source = "${rootPath}/configs/hypr/colors.lua";
      output = ".config/hypr/colors.lua";
    };
  };
}
