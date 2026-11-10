{
  den.aspects.system.nixos =
    { pkgs, lib, ... }:
    {
      nix.settings = {
        experimental-features = [
          "pipe-operator"
          "nix-command"
          "flakes"
        ];
        trusted-users = [ "@wheel" ];
        max-jobs = lib.mkDefault 1;
        cores = lib.mkDefault 2;
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
      # builds and VM tests get the CPU and the disk only in the moments no normal process is waiting
      # for them, so a gate never stalls typing, audio or video. an open program that's only waiting
      # for input uses neither, so builds still get nearly the whole machine.
      nix.daemonCPUSchedPolicy = "idle";
      nix.daemonIOSchedClass = "idle";
      # a build's scratch tree lives in RAM, so a check that writes millions of small files never
      # puts them on the disk, and only what a build keeps reaches the store. zram backs overflow.
      fileSystems."/nix/var/nix/b" = {
        device = "tmpfs";
        fsType = "tmpfs";
        options = [
          "size=16G"
          "mode=0755"
        ];
      };
      # btrfs commits every dirty page in one transaction, and a program's fsync waits for all of
      # it. capping dirty data keeps each commit small, so a save never waits behind gigabytes of
      # someone else's writes; the default of a fifth of RAM let a gate queue several.
      boot.kernel.sysctl = {
        "vm.dirty_bytes" = 256 * 1024 * 1024;
        "vm.dirty_background_bytes" = 64 * 1024 * 1024;
      };

      nixpkgs.config.allowUnfree = true;

      time.timeZone = "America/Los_Angeles";
      i18n.defaultLocale = "en_US.UTF-8";

      services.printing.enable = true;

      services.journald.settings.Journal = {
        SystemMaxUse = "1G";
        SystemKeepFree = "10G";
      };
      systemd.coredump.settings.Coredump = {
        MaxUse = "512M";
        KeepFree = "10G";
      };

      security.sudo.wheelNeedsPassword = true;

      services.pulseaudio.enable = false;
      security.rtkit.enable = true;
      services.pipewire = {
        enable = true;
        alsa.enable = true;
        alsa.support32Bit = true;
        pulse.enable = true;
      };

      hardware.bluetooth = {
        enable = true;
        powerOnBoot = true;
      };
      services.blueman.enable = true;

      services.fstrim.enable = true;

      # noto covers broad scripts and emoji; the nerd fonts cover terminal glyphs.
      fonts = {
        packages = with pkgs; [
          nerd-fonts.jetbrains-mono
          nerd-fonts.symbols-only
          noto-fonts-color-emoji
          noto-fonts-cjk-sans
          liberation_ttf
          maple-mono.NF
          noto-fonts
          fira-code
          inter
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

      boot.kernelParams = [ "nowatchdog" ];

      # activation restores user ownership after root writes to /etc/skadi.
      systemd.tmpfiles.rules = [ "Z /etc/skadi - feltfomo feltfomo - -" ];

      environment.systemPackages = with pkgs; [
        efibootmgr
        grub2_efi
        wget
        curl
        git
        fzf
        jq
      ];

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
