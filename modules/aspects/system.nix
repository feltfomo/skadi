_: {
  den.aspects.system.nixos =
    { pkgs, ... }:
    {
      nix.settings = {
        experimental-features = [
          "nix-command"
          "flakes"
          "pipe-operator"
        ];
        trusted-users = [ "@wheel" ];
        # prevents hanging on offline caches
        connect-timeout = 5;
      };

      # automatic garbage collection (from wiki)
      nix.gc = {
        automatic = true;
        dates = "weekly";
        options = "--delete-older-than 30d";
      };
      # deduplicate store with hardlinks on a schedule
      # better than auto-optimise-store which slows down every build
      nix.optimise.automatic = true;

      nixpkgs.config.allowUnfree = true;

      time.timeZone = "America/Los_Angeles";
      i18n.defaultLocale = "en_US.UTF-8";

      # sudo needs a password
      security.sudo.wheelNeedsPassword = true;

      services.openssh = {
        enable = true;
        settings = {
          # disable password auth, require keys
          PasswordAuthentication = false;
          KbdInteractiveAuthentication = false;
          PermitRootLogin = "no";
        };
      };

      # install grub
      boot.loader = {
        grub = {
          enable = true;
          device = "nodev";
          efiSupport = true;
        };
        efi.canTouchEfiVariables = true;
      };

      environment.systemPackages = with pkgs; [
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

      # enable dconf, neovim, fish, and nix-ld
      programs = {
        dconf.enable = true;
        neovim = {
          enable = true;
          defaultEditor = true;
        };
        fish.enable = true;
        nix-ld.enable = true;
      };
      services.flatpak.enable = true;
    };
}
