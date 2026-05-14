{ ... }:
{
  flake.nixosModules.qt =
    { ... }:
    {
      # enable qt and set style and platformTheme
      qt = {
        enable = true;
        style = "kvantum";
        platformTheme = "qt5ct";
      };
    };
}
