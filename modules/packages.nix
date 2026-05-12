{ pkgs, ... }:
{
  environment = {
    systemPackages = with pkgs; [
      gcc
      git
      nil
      vlc
      nixd
      glib
      wget
      curl
      xclip
      grub2_efi
      efibootmgr
      wl-clipboard
      wayland-utils
      libsForQt5.qt5ct
      qt6Packages.qt6ct
      gsettings-desktop-schemas
      libsForQt5.qtstyleplugin-kvantum
    ];
  };
}
