{
  inputs,
  den,
  ...
}:
{
  den.aspects.feltfomo = {
    includes = with den.aspects; [
      den.batteries.define-user
      den.batteries.primary-user
      (den.batteries.user-shell "fish")

      zed
      obs
      dms
      helix
      thunar
      nvim
      niri
      shell
      kitty
      qt-hm
      herdr
      fuzzel
      ghostty
      theming
      mangowm
      firefox
      noctalia
      hyprland
      spicetify
      caelestia
      gtk-theme
      bootstrap-repos
    ];

    nixos =
      {
        config,
        ...
      }:
      {
        sops.secrets."feltfomo-password".neededForUsers = true;
        skadi.provision.secrets.feltfomo-password = {
          method = "mkpasswd";
          prompt = "login password for feltfomo";
        };

        # logseq pulls an eol electron
        nixpkgs.config.permittedInsecurePackages = [ "electron-39.8.10" ];

        # gifski 1.34.0 intermittently failed its timing test
        nixpkgs.overlays = [
          (_: prev: {
            gifski = prev.gifski.overrideAttrs (_: {
              doCheck = false;
            });
          })
        ];

        users.users.feltfomo = {
          group = "feltfomo";
          # an unprovisioned feltfomo-password leaves the account without a login
          # run `nixos-rebuild test` and verify a fresh tty before switching
          hashedPasswordFile = config.sops.secrets."feltfomo-password".path;
          extraGroups = [
            "video"
            "docker"
            "ydotool"
          ];
          # notion-sync must start before the first login
          linger = true;

          # system.nix disables password auth, so khion uses feltfomo's github key
          openssh.authorizedKeys.keys = [
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINKAWZ+4L7E0osgTA8eybrsmUoTUtBSzEaE4ytD+rcPO 241195017+feltfomo@users.noreply.github.com"
          ];
        };
        users.groups.feltfomo = { };

        environment.persistence."/persist".users.feltfomo.directories = [
          "Downloads"
          "Documents"
          "Pictures"
          "Videos"
          "Music"
          ".config"
          ".ssh"
          "Projects"
        ];
      };

    homeManager =
      {
        pkgs,
        lib,
        ...
      }:
      let
        # logseq hangs in the nixos-unstable buildphase
        # nixpkgs-logseq carries the fix from nixpkgs #536292
        logseqPkgs = import inputs.nixpkgs-logseq {
          system = pkgs.stdenv.hostPlatform.system;
          config = {
            allowUnfree = true;
            allowInsecurePredicate = p: builtins.elem (pkgs.lib.getName p) [ "electron" ];
          };
        };
      in
      {
        # the wiped root removed ~/.steam before the steam wrapper's repair step
        # repair then failed while creating ~/.steam/steam with "no such file or directory"
        home.activation.steamSymlinks = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          run mkdir -p "$HOME/.steam"
          run ln -sfn "$HOME/.local/share/Steam" "$HOME/.steam/steam"
          run ln -sfn "$HOME/.local/share/Steam" "$HOME/.steam/root"
        '';

        programs.git = {
          enable = true;
          settings.user = {
            name = "feltfomo";
            email = "241195017+feltfomo@users.noreply.github.com";
          };
        };

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
          gifski
          zenity
          nushell
          spotatui
          python3
          lazygit
          devenv
          equibop
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
          qbittorrent
          tor-browser
          imagemagick
          appimage-run
          osu-lazer-bin
          jetbrains.idea
          ayugram-desktop
          translate-shell
          opencode-desktop
          logseqPkgs.logseq
          inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.pi
          inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default
          inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.twilight
          inputs.illogical-impulse-shell.packages.${pkgs.stdenv.hostPlatform.system}.runtime
          inputs.illogical-impulse-shell.packages.${pkgs.stdenv.hostPlatform.system}.end4-pc-runtime
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
