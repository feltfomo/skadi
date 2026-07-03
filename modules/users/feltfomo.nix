{ inputs, den, ... }:
{
  den.aspects.feltfomo = {
    includes = [
      den.batteries.define-user
      den.batteries.primary-user

      # home aspects must be included on the user. den dropped host to user
      # homeManager forwarding in v0.13, so host aspects no longer reach this
      # home. aspects that also define nixos still contribute it to the host.
      den.aspects.shell
      den.aspects.theming
      den.aspects.hyprland
      den.aspects.kitty
      den.aspects.fuzzel
      den.aspects.spicetify
      den.aspects.noctalia
      den.aspects.walker
      den.aspects.firefox
      den.aspects.qt-hm
    ];

    # define-user makes a normal user and sets the home dir,
    # primary-user adds wheel and networkmanager
    nixos =
      { pkgs, config, ... }:
      {
        # logseq pulls an eol electron
        nixpkgs.config.permittedInsecurePackages = [ "electron-39.8.10" ];

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
          # decrypted by sops-nix from secrets/secrets.yaml. provision it BEFORE
          # rebuilding or the account has no password -- use `nixos-rebuild test`
          # and confirm login on a fresh tty before `switch` (see README).
          hashedPasswordFile = config.sops.secrets."feltfomo-password".path;
          shell = pkgs.fish;
          extraGroups = [
            "video"
            "docker"
          ];
          # lingering lets the notion-sync user service start at boot, no login needed
          linger = true;
        };
        users.groups.feltfomo = { };

        # user directories that survive the boot rollback
        environment.persistence."/persist".users.feltfomo.directories = [
          "Downloads"
          "Documents"
          "Pictures"
          "Videos"
          "Music"
          ".config"
          ".local"
          ".ssh"
          # notion-sync dirs
          "Projects"
        ];
      };

    homeManager =
      { pkgs, ... }:
      let
        # logseq's buildPhase hangs on nixos-unstable until nixpkgs #536292 lands
        # there; pull it from master (which has the fix) meanwhile.
        logseqPkgs = import inputs.nixpkgs-logseq {
          system = pkgs.stdenv.hostPlatform.system;
          config = {
            allowUnfree = true;
            allowInsecurePredicate = p: builtins.elem (pkgs.lib.getName p) [ "electron" ];
          };
        };
      in
      {
        # git identity
        programs.git = {
          enable = true;
          settings.user = {
            name = "feltfomo";
            email = "241195017+feltfomo@users.noreply.github.com";
          };
        };

        # ssh client: a user-service agent auto-loads the key so git pushes work
        # after a fresh boot with no manual ssh-add. the key lives in ~/.ssh
        # (persisted above); this only wires the agent and points github at it.
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
          vlc
          grim
          slurp
          brave
          satty
          heroic
          gifski
          zenity
          logseqPkgs.logseq
          python3
          equibop
          gamemode
          hyprshot
          obsidian
          grimblast
          superfile
          librewolf
          fastfetch
          tesseract
          proton-vpn
          winetricks
          hyprpicker
          zed-editor
          evil-helix
          qbittorrent
          tor-browser
          imagemagick
          appimage-run
          ayugram-desktop
          translate-shell
          jetbrains.idea-oss
          inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.twilight
          inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default
          (prismlauncher.override {
            jdks = [
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
