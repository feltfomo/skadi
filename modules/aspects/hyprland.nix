{
  inputs,
  lib,
  rootPath,
  ...
}:
let
  program = import ../_lib/program.nix { inherit lib; };

  # Event-driven watcher: keeps any window that is playing audio (Spotify, a
  # browser tab, etc.) fully opaque so it does not dim while it is inactive.
  audioOpacityService =
    { pkgs, ... }:
    let
      hyprctlPkg = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
      # The daemon body lives in scripts/audio-opacity.sh (kept out of this aspect
      # so the file stays readable, same pattern as installer.nix). writeShellApplication
      # supplies the bash shebang, `set -euo pipefail`, and a PATH from runtimeInputs.
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

  base = program {
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
    templates = [
      {
        name = "colors.lua";
        templateFile = "${rootPath}/configs/hypr/colors.lua";
        subdir = "hyprland/";
      }
    ];
    noctaliaConfig = {
      _fileName = "hyprland";
      theme.templates.user.hyprland = {
        input_path = "~/.config/noctalia/templates/hyprland/colors.lua";
        output_path = "~/.config/hypr/colors.lua";
      };
    };
  };
in
{
  den.aspects.hyprland = base // {
    nixos =
      { pkgs, ... }:
      {
        programs.hyprland = {
          enable = true;
          package = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
          portalPackage =
            inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland;
        };

        # flatpak lives with the desktop that provides its xdg portal, not in
        # base. programs.hyprland already enables xdg.portal (+ the hyprland
        # backend), so flatpak's only hard dependency is satisfied right here.
        # a lean base install (generic/owner) has no desktop -> no app-store.
        services.flatpak.enable = true;
      };
  };
}
