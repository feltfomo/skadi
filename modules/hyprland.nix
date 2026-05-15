{ inputs, rootPath, ... }:
{
  flake.modules.nixos.hyprland =
    { pkgs, ... }:
    {
      # enable hyprland
      programs.hyprland = {
        enable = true;
        package = inputs.hyprland.packages.${pkgs.system}.hyprland;
        portalPackage = inputs.hyprland.packages.${pkgs.system}.xdg-desktop-portal-hyprland;
      };

      # manage hyprland config with hjem
      hjem.users.feltfomo.files = {
        ".config/hypr".source = "${rootPath}/configs/hypr";
      };
    };
}
