{
  inputs,
  rootPath,
  config,
  ...
}:
{
  flake.modules.nixos.hyprland =
    { pkgs, ... }:
    {
      # enable hyprland with flake packages
      programs.hyprland = {
        enable = true;
        package = inputs.hyprland.packages.${pkgs.system}.hyprland;
        portalPackage = inputs.hyprland.packages.${pkgs.system}.xdg-desktop-portal-hyprland;
      };

      imports = [
        (config.flake.factory.program {
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
        })
      ];
    };
}
