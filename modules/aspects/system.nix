{
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
        # offline substitutes get one short connection attempt instead of stalling builds
        connect-timeout = 5;
        min-free = 10 * 1024 * 1024 * 1024;
        max-free = 30 * 1024 * 1024 * 1024;
      };

      nix.gc = {
        automatic = true;
        dates = "weekly";
        options = "--delete-older-than 30d";
      };
      # hardlink dedup on a schedule; auto-optimise-store would slow every build
      nix.optimise.automatic = true;

      nixpkgs.config.allowUnfree = true;

      time.timeZone = "America/Los_Angeles";
      i18n.defaultLocale = "en_US.UTF-8";

      services.printing.enable = true;

      services.journald.extraConfig = ''
        SystemMaxUse=1G
        SystemKeepFree=10G
      '';
      systemd.coredump.settings.Coredump = {
        MaxUse = "512M";
        KeepFree = "10G";
      };

      security.sudo.wheelNeedsPassword = true;

      # audio. pipewire replaces pulseaudio; the pulse shim is what provides
      # pactl, which the steam runtime shells out to -- without it steam logged
      # "pactl command not found" and skipped audio device setup.
      services.pulseaudio.enable = false;
      security.rtkit.enable = true;
      services.pipewire = {
        enable = true;
        alsa.enable = true;
        alsa.support32Bit = true;
        pulse.enable = true;
      };

      # bluetooth. /var/lib/bluetooth is already in the impermanence persist
      # list, so pairings were meant to survive the rollback -- but the radio
      # itself was never turned on. blueman is the manager for the hyprland
      # session; gnome brings its own.
      hardware.bluetooth = {
        enable = true;
        powerOnBoot = true;
      };
      services.blueman.enable = true;

      # weekly trim for the luks+btrfs ssd root
      services.fstrim.enable = true;

      # noto covers broad scripts and emoji; the nerd fonts cover terminal glyphs.
      fonts = {
        packages = with pkgs; [
          noto-fonts
          noto-fonts-cjk-sans
          noto-fonts-color-emoji
          liberation_ttf
          inter
          fira-code
          maple-mono.NF
          nerd-fonts.jetbrains-mono
          nerd-fonts.symbols-only
        ];
        fontconfig.defaultFonts = {
          serif = [ "Maple Mono" ];
          sansSerif = [ "Maple Mono" ];
          monospace = [ "Maple Mono NF" ];
        };
      };

      services.openssh = {
        enable = true;
        settings = {
          PasswordAuthentication = false;
          KbdInteractiveAuthentication = false;
          PermitRootLogin = "no";
        };
      };

      # host-agnostic kernel watchdog disable
      boot.kernelParams = [ "nowatchdog" ];

      # make /etc/skadi user-editable without sudo (zed "permission denied" on save).
      # the Z rule re-owns on every activation, self-healing after a root-cp install.
      systemd.tmpfiles.rules = [ "Z /etc/skadi - feltfomo feltfomo - -" ];

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
        # pipewire ships the pulse server but not pactl, which steam invokes directly
        pulseaudio
        grub2_efi
        efibootmgr
        gsettings-desktop-schemas
      ];

      # ios device support
      services.usbmuxd.enable = true;

      programs = {
        dconf.enable = true;
        neovim = {
          enable = true;
          defaultEditor = true;
        };
        fish.enable = true;
        nix-ld.enable = true;
      };
    };
}
