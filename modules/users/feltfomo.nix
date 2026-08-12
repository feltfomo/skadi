{
  inputs,
  den,
  ...
}: {
  den.aspects.feltfomo = {
    includes = with den.aspects; [
      den.batteries.define-user
      den.batteries.primary-user

      # den v0.13 dropped host-to-user homeManager forwarding
      # aspects that also define nixos still reach the host
      shell
      theming
      hyprland
      mangowm
      niri
      kitty
      ghostty
      nvim
      spicetify
      noctalia
      dms
      caelestia
      firefox
      qt-hm
      zed
      herdr
      fastfetch

      # clone wallpaper and notion-sync mapping repos on first boot
      bootstrap-repos
    ];

    # define-user makes a normal user and sets the home dir,
    # primary-user adds wheel and networkmanager
    nixos = {
      pkgs,
      config,
      ...
    }: {
      # login password + how the installer provisions it, owned next to the
      # user that needs it. feltfomo exists on BOTH khion and lumi, so the
      # hash rides secrets/lumi.yaml (encrypted to khion + lumi) instead of
      # khion-only secrets.yaml -- otherwise sops-nix cannot decrypt it on
      # lumi at activation and the account boots with no password. mirrors
      # grandpa; khion-only secrets (notion-token, hermes) stay in secrets.yaml.
      sops.secrets."feltfomo-password" = {
        neededForUsers = true;
        sopsFile = ../../secrets/lumi.yaml;
      };
      skadi.provision.secrets.feltfomo-password = {
        method = "mkpasswd";
        prompt = "login password for feltfomo";
      };

      # logseq pulls an eol electron
      nixpkgs.config.permittedInsecurePackages = ["electron-39.8.10"];

      # gifski 1.34.0 has a flaky timing test
      nixpkgs.overlays = [
        (_: prev: {
          gifski = prev.gifski.overrideAttrs (_: {
            doCheck = false;
          });
        })
      ];

      users.users.feltfomo = {
        group = "feltfomo";
        # decrypted by sops-nix from secrets/lumi.yaml (khion + lumi).
        # provision it before rebuilding or the account has no password
        # use `nixos-rebuild test` and confirm login on a fresh tty before switch
        hashedPasswordFile = config.sops.secrets."feltfomo-password".path;
        shell = pkgs.fish;
        extraGroups = [
          "video"
          "docker"
          "ydotool"
        ];
        # lingering lets the notion-sync user service start at boot, no login needed
        linger = true;

        # ssh in from khion. system.nix sets PasswordAuthentication = false
        # (key-only), so khion's key must be authorized explicitly -- this is
        # the same ~/.ssh/id_ed25519 feltfomo pushes to github with.
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINKAWZ+4L7E0osgTA8eybrsmUoTUtBSzEaE4ytD+rcPO 241195017+feltfomo@users.noreply.github.com"
        ];
      };
      users.groups.feltfomo = {};

      # user directories that survive the boot rollback
      environment.persistence."/persist".users.feltfomo.directories = [
        "Downloads"
        "Documents"
        "Pictures"
        "Videos"
        "Music"
        ".config"
        # ~/.local persists the real Steam install + games at
        # ~/.local/share/Steam. do not persist ~/.steam -- it holds only
        # regenerable symlinks that steam relinks to ~/.local on every launch
        # ("Repairing installation, linking ..."). persisting it once froze a
        # malformed ~/.steam/steam (a real dir where the symlink belongs)
        # across reboots -> recurring "Couldn't set up Steam data". leaving
        # ~/.steam on the wiped root clears any bad state each boot so steam
        # rebuilds it clean. drift only happens if you persist ~/.steam
        # without ~/.local, not this way around.
        ".local"
        ".ssh"
        # notion-sync dirs
        "Projects"
      ];
    };

    homeManager = {
      pkgs,
      lib,
      ...
    }: let
      # logseq's buildPhase hangs on nixos-unstable until nixpkgs #536292 lands
      # there; pull it from master (which has the fix) meanwhile.
      logseqPkgs = import inputs.nixpkgs-logseq {
        system = pkgs.stdenv.hostPlatform.system;
        config = {
          allowUnfree = true;
          allowInsecurePredicate = p: builtins.elem (pkgs.lib.getName p) ["electron"];
        };
      };
    in {
      # ~/.steam is not persisted (see the persist list above), so it is gone
      # on the freshly-wiped root each boot, and the nixos steam wrapper's
      # "Repairing installation" step does not mkdir it -> "ln: failed to
      # create symbolic link '~/.steam/steam': No such file or directory".
      # recreate the symlinks steam needs on every activation with ln -sfn
      # (idempotent; overwrites whatever is there, so it can never freeze a
      # bad ~/.steam/steam like persisting it did). they point at the
      # persisted install; steam adds bin32/bin64/pid alongside them fine.
      home.activation.steamSymlinks = lib.hm.dag.entryAfter ["writeBoundary"] ''
        run mkdir -p "$HOME/.steam"
        run ln -sfn "$HOME/.local/share/Steam" "$HOME/.steam/steam"
        run ln -sfn "$HOME/.local/share/Steam" "$HOME/.steam/root"
      '';

      # git identity
      programs.git = {
        enable = true;
        settings.user = {
          name = "feltfomo";
          email = "241195017+feltfomo@users.noreply.github.com";
        };
      };

      # the user agent reloads the persisted key after boot
      # github uses that agent for git pushes
      services.ssh-agent.enable = true;
      programs.ssh = {
        enable = true;
        enableDefaultConfig = false;
        settings = {
          "*".AddKeysToAgent = "yes";
          "github.com" = {
            IdentityFile = "~/.ssh/id_ed25519";
            IdentitiesOnly = true;
          };
        };
      };

      home.packages = with pkgs; [
        (pkgs.writeScriptBin "sops-edit" ''
          #!${pkgs.nushell}/bin/nu
          ${builtins.readFile ../../scripts/sops-edit.nu}
        '')
        vlc
        grim
        slurp
        brave
        satty
        heroic
        sgdboop
        gamescope
        gifski
        zenity
        nushell
        spotatui
        logseqPkgs.logseq
        python3
        lazygit
        equibop
        gamemode
        hyprshot
        obsidian
        grimblast
        superfile
        librewolf
        tesseract
        alejandra
        proton-vpn
        winetricks
        hyprpicker
        motrix-next
        evil-helix
        qbittorrent
        tor-browser
        imagemagick
        appimage-run
        ayugram-desktop
        translate-shell
        opencode-desktop
        inputs.illogical-impulse-shell.packages.${pkgs.stdenv.hostPlatform.system}.runtime
        inputs.illogical-impulse-shell.packages.${pkgs.stdenv.hostPlatform.system}.end4-pc-runtime
        inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.twilight
        inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default
        inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.pi
        (prismlauncher.override {
          jdks = [
            jdk8
            jdk21
            jdk17
            pkgs.graalvm-oracle-21
            graalvmPackages.graalvm-ce
          ];
        })
      ];
    };
  };
}
