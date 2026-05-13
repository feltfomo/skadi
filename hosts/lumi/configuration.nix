{ ... }:
{
  imports = [
    ./impermanence.nix
    ./environment.nix
    ./networking.nix
    ./hardware.nix
    ./disko.nix
    ../../modules/hyprland.nix
    ../../modules/packages.nix
    ../../modules/settings.nix
    ../../modules/programs.nix
    ../../modules/security.nix
    ../../modules/openssh.nix
    ../../modules/thunar.nix
    ../../modules/steam.nix
    ../../modules/gnome.nix
    ../../modules/user.nix
    ../../modules/boot.nix
    ../../modules/qt.nix
    ../../modules/gc.nix
  ];

  system.stateVersion = "25.11";
}
