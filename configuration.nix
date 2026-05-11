{ ... }:
{
  imports = [
    ./hosts/lumi/hardware.nix
    ./modules/hyprland.nix
    ./modules/packages.nix
    ./impermanence.nix
    ./networking.nix
    ./disko.nix
    ./boot.nix
    ./user.nix
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

  programs = {
    neovim = {
      enable = true;
      defaultEditor = true;
    };

    nix-ld.enable = true;
  };

  environment = {
    variables = {
      EDITOR = "nvim";
    };
  };

  qt = {
    enable = true;
    style = "kvantum";
    platformTheme = "qt5ct";
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
