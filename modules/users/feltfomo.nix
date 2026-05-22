{ inputs, ... }:
{
  flake.modules.nixos.feltfomo =
    { pkgs, ... }:
    {
      # set feltfomo user
      users.users.feltfomo = {
        isNormalUser = true;
        group = "feltfomo";
        hashedPassword = "$y$j9T$HT.mVqk50c03QSEv1rqlP0$5albZpdKB3hIndg.ecMfZ2ZxaDPEwDx5AbZKLaY9tY8";
        shell = pkgs.fish;
        extraGroups = [
          "wheel"
          "networkmanager"
          "video"
        ];
      };
      users.groups.feltfomo = { };
      hjem.users.feltfomo = {
        enable = true;
        user = "feltfomo";
        directory = "/home/feltfomo";
      };
      home-manager.users.feltfomo.home = {
        username = "feltfomo";
        homeDirectory = "/home/feltfomo";
        stateVersion = "25.11";
        packages = with pkgs; [
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
          tor-browser
          imagemagick
          appimage-run
          ayugram-desktop
          translate-shell
          inputs.walker.packages.${system}.default
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
