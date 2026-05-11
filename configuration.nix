{ config, pkgs, lib, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    ./impermanence.nix
    <impermanence/nixos.nix>
    <disko/module.nix>
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.initrd.systemd.enable = true;

  networking.hostName = "lumi";
  networking.networkmanager.enable = true;

  time.timeZone = "America/Los_Angeles";

  i18n.defaultLocale = "en_US.UTF-8";

  hardware.cpu.intel.updateMicrocode = true;

  users.users.feltfomo = {
    isNormalUser = true;
    hashedPassword = "$y$j9T$HT.mVqk50c03QSEv1rqlP0$5albZpdKB3hIndg.ecMfZ2ZxaDPEwDx5AbZKLaY9tY8";
    extraGroups = [ "wheel" "networkmanager" "video" ];
  };

  programs.hyprland.enable = true;

  programs.neovim = {
    enable = true;
    defaultEditor = true;
  };

  environment.systemPackages = with pkgs; [
    git
    wget
    curl
    fastfetch
  ];

  services.openssh.enable = true;

  security.sudo.wheelNeedsPassword = true;

  system.stateVersion = "25.11";
}
