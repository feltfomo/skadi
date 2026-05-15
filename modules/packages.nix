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
          gsettings-desktop-schemas
        ];
      };
    };
}
