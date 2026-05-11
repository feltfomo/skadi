{ pkgs, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./impermanence.nix
    ./networking.nix
    ./disko.nix
    ./boot.nix
    ./user.nix
    <impermanence/nixos.nix>
    <disko/module.nix>
  ];

  time.timeZone = "America/Los_Angeles";

  i18n.defaultLocale = "en_US.UTF-8";

  hardware.cpu.intel.updateMicrocode = true;

  programs.hyprland = {
    enable = true;
    withUWSM = true;
    xwayland.enable = true;
  };

  programs.neovim = {
    enable = true;
    defaultEditor = true;
  };

  environment.systemPackages = with pkgs; [
    gcc
    git
    nil
    nixd
    wget
    curl
    kitty
    brave
    fuzzel
    firefox
    fastfetch
    zed-editor
  ];

  services = {
    displayManager.sddm = {
      enable = true;
      wayland.enable = true;
    };
  };

  services.openssh.enable = true;

  security.sudo.wheelNeedsPassword = true;

  system.stateVersion = "25.11";
}
