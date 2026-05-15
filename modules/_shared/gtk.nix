{ pkgs, ... }:
{
  # set gtk color scheme and icon theme for feltfomo
  home-manager.users.feltfomo.gtk = {
    enable = true;
    colorScheme = "dark";
    iconTheme = {
      name = "Papirus-Dark";
      package = pkgs.papirus-icon-theme;
    };
  };
}
