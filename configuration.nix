{ pkgs, inputs, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./impermanence.nix
    ./networking.nix
    ./disko.nix
    ./boot.nix
    ./user.nix
    ./impermanence.nix
    ./disko.nix
  ];

  nix.settings = {
    substituters = [ "https://hyprland.cachix.org" ];
    trusted-substituters = [ "https://hyprland.cachix.org" ];
    trusted-public-keys = [ "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc=" ];
    experimental-features = [
      "nix-command"
      "flakes"
    ];
  };

  time.timeZone = "America/Los_Angeles";

  i18n.defaultLocale = "en_US.UTF-8";

  hardware.cpu.intel.updateMicrocode = true;

  programs = {
    hyprland = {
      enable = true;
      package = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
      portalPackage =
        inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland;
    };

    neovim = {
      enable = true;
      defaultEditor = true;
    };

    nix-ld.enable = true;
  };

  environment = {
    systemPackages = with pkgs; [
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
      wl-clipboard
      libsForQt5.qt5ct
      qt6Packages.qt6ct
      libsForQt5.qtstyleplugin-kvantum
      inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default
    ];

    variables.EDITOR = "nvim";
  };

  qt = {
    enable = true;
    platformTheme = "kvantum";
  };

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
