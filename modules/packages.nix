{ pkgs, ... }:
{
  environment = {
    systemPackages = with pkgs; [
      gcc
      git
      nil
      nixd
      glib
      wget
      curl
      grub2_efi
      efibootmgr
      wl-clipboard
      libsForQt5.qt5ct
      qt6Packages.qt6ct
      gsettings-desktop-schemas
      libsForQt5.qtstyleplugin-kvantum
    ];
  };
}
