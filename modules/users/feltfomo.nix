{ inputs, den, ... }:
{
  den.aspects.feltfomo = {
    includes = [
      den.batteries.define-user
      den.batteries.primary-user
      den.aspects.spicetify

      # home aspects must be included on the user. den dropped host to user
      # homeManager forwarding in v0.13, so host aspects no longer reach this
      # home. aspects that also define nixos still contribute it to the host.
      den.aspects.shell
      den.aspects.theming
      den.aspects.hyprland
      den.aspects.kitty
      den.aspects.fuzzel
      den.aspects.noctalia
      den.aspects.walker
      den.aspects.firefox
      den.aspects.qt-hm
    ];

    # define-user makes a normal user and sets the home dir,
    # primary-user adds wheel and networkmanager
    nixos =
      { pkgs, ... }:
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
          hashedPassword = "$y$j9T$HT.mVqk50c03QSEv1rqlP0$5albZpdKB3hIndg.ecMfZ2ZxaDPEwDx5AbZKLaY9tY8";
          shell = pkgs.fish;
          extraGroups = [ "video" ];
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
        ];
      };

    homeManager =
      { pkgs, ... }:
      {
        # git identity
        programs.git = {
          enable = true;
          settings.user = {
            name = "feltfomo";
            email = "241195017+feltfomo@users.noreply.github.com";
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
          logseq
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
