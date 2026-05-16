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
      programs.hyprland = {
        enable = true;
        package = inputs.hyprland.packages.${pkgs.system}.hyprland;
        portalPackage = inputs.hyprland.packages.${pkgs.system}.xdg-desktop-portal-hyprland;
      };

      imports = [
        (config.flake.factory.program {
          files = [
            {
              dest = ".config/hypr";
              src = "${rootPath}/configs/hypr";
            }
          ];
        })
      ];
    };
}
