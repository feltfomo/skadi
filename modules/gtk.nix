{ ... }:
{
  flake.nixosModules.gtk =
    { pkgs, ... }:
    {
      home-manager.users.feltfomo.gtk = {
        enable = true;
        colorScheme = "dark";
        iconTheme = {
          name = "Papirus-Dark";
          package = pkgs.papirus-icon-theme;
        };
      };
    };
}
