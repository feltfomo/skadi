{ pkgs, inputs, ... }:
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
      kitty
      brave
      fuzzel
      fastfetch
      grub2_efi
      efibootmgr
      zed-editor
      wl-clipboard
      libsForQt5.qt5ct
      qt6Packages.qt6ct
      catppuccin-kvantum
      rose-pine-kvantum
      gsettings-desktop-schemas
      libsForQt5.qtstyleplugin-kvantum
      inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default
    ];
  };
}
