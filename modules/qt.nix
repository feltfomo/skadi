{ ... }:
{
  flake.nixosModules.qt =
    { ... }:
    {
      qt = {
        enable = true;
        style = "kvantum";
        platformTheme = "qt5ct";
      };
    };
}
