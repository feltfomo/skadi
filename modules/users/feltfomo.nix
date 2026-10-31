{
  den,
  ...
}:
{
  den.aspects.feltfomo = {
    includes = with den.aspects; [
      (den.batteries.user-shell "fish")
      den.batteries.primary-user
      den.batteries.define-user
      native-debugging
      bootstrap-repos
      jvm-development
      lua-development
      nix-development
      screen-capture
      prismlauncher
      claude-code
      image-tools
      qbittorrent
      steam-tools
      translation
      zen-browser
      proton-vpn
      sops-tools
      winetricks
      gtk-theme
      spicetify
      superfile
      tty-clock
      appimage
      hyprland
      noctalia
      obsidian
      rayburst
      spotatui
      vscodium
      ayugram
      end4-pc
      equibop
      ghostty
      lazygit
      mangowm
      nushell
      theming
      wooting
      devenv
      fuzzel
      heroic
      linear
      python
      tablet
      thunar
      brave
      codex
      helix
      herdr
      kitty
      lunar
      qt-hm
      shell
      idea
      niri
      nvim
      dms
      obs
      osu
      vlc
      zed
      gh
      pi
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

        users.users.feltfomo = {
          group = "feltfomo";
          linger = true;
          # an unprovisioned feltfomo-password leaves the account without a login
          # run `nixos-rebuild test` and verify a fresh tty before switching
          hashedPasswordFile = config.sops.secrets."feltfomo-password".path;
          extraGroups = [
            "ydotool"
            "docker"
            "uinput"
            "video"
            "input"
          ];
          # system.nix disables password auth, so khion uses feltfomo's github key
          openssh.authorizedKeys.keys = [
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINKAWZ+4L7E0osgTA8eybrsmUoTUtBSzEaE4ytD+rcPO 241195017+feltfomo@users.noreply.github.com"
          ];
        };
        users.groups.feltfomo = { };

        # ssh can't ask about an unknown host from an agent or a service, so
        # github's key can't wait for a first interactive connection.
        programs.ssh.knownHosts."github.com".publicKey =
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
      };

    homeManager = {
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

    };
  };
}
