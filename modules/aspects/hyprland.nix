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
    with pkgs;
    let
      hyprctlPkg = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
      audio-opacity = writeShellApplication {
        name = "audio-opacity";
        runtimeInputs = [
          jq
          gawk
          procps
          coreutils
          hyprctlPkg
          pulseaudio
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
        programs.ydotool.enable = true;
        services.flatpak.enable = true;

        # pin ScreenCast to the hyprland portal (not gnome's) to avoid black/empty screenshares in discord/equibop keep FileChooser on gtk.
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
    theme = {
      id = "hyprland";
      output = ".config/hypr/colors.lua";
      reload = "hyprctl reload";
      renderers = {
        caelestia = {
          source = "${rootPath}/configs/hypr/caelestia-colors.lua";
          placedAs = "colors.lua";
        };
        illogical-impulse = {
          source = "${rootPath}/configs/hypr/colors.lua";
          sharedWith = [ "end4-pc" ];
        };
      };
    };
  };
}
