{ ... }:
{
  flake.modules.nixos.packages =
    { pkgs, ... }:
    {
      environment = {
        systemPackages = with pkgs; [
          jq
          gcc
          git
          fzf
          nil
          nixd
          glib
          wget
          curl
          xclip
          ffmpeg
          cliphist
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
    };
}
