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
    ../../modules/sddm.nix
    ../../modules/user.nix
    ../../modules/boot.nix
    ../../modules/qt.nix
  ];

  system.stateVersion = "25.11";
}
