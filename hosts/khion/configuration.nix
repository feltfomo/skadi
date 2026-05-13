{ ... }:
{
  imports = [
    ./impermanence.nix
    ./environment.nix
    ./networking.nix
    ./hardware.nix
    ./nvidia.nix
    ./disko.nix
    ../../modules/hyprland.nix
    ../../modules/packages.nix
    ../../modules/settings.nix
    ../../modules/programs.nix
    ../../modules/security.nix
    ../../modules/openssh.nix
    ../../modules/thunar.nix
    ../../modules/steam.nix
    ../../modules/user.nix
    ../../modules/boot.nix
    ../../modules/gtk.nix
    ../../modules/qt.nix
    ../../modules/gc.nix
  ];

  system.stateVersion = "25.11";
}
