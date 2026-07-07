{
  inputs,
  lib,
  rootPath,
  ...
}:
let
  program = import ../_lib/program.nix { inherit lib; };
in
{
  den.aspects.hyprland = {
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
  }
  // program {
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
      {
        dest = ".config/hypr/helpers/scratchpad.lua";
        src = "${rootPath}/configs/hypr/helpers/scratchpad.lua";
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
}
