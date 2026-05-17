{ pkgs, ... }:
{
  # enable qt and set style and platformTheme
  qt = {
    enable = true;
    platformTheme = "qt5ct";
  };

  environment.systemPackages = with pkgs; [
    libsForQt5.qt5ct
    qt6Packages.qt6ct
  ];
}
