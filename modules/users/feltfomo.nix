{ inputs, ... }:
{
  flake.nixosModules.feltfomo =
    { pkgs, ... }:
    {
      # set feltfomo user
      users.users.feltfomo = {
        isNormalUser = true;
        group = "feltfomo";
        hashedPassword = "$y$j9T$HT.mVqk50c03QSEv1rqlP0$5albZpdKB3hIndg.ecMfZ2ZxaDPEwDx5AbZKLaY9tY8";
        shell = pkgs.fish;
        # sudo, network, and video groups
        extraGroups = [
          "wheel"
          "networkmanager"
          "video"
        ];
      };
      # user group
      users.groups.feltfomo = { };
      # set feltfomo as a hjem user and sets dir
      hjem.users.feltfomo = {
        enable = true;
        user = "feltfomo";
        directory = "/home/feltfomo";
      };
      # home-manager config
      home-manager.users.feltfomo.home = {
        username = "feltfomo";
        homeDirectory = "/home/feltfomo";
        stateVersion = "25.11";
        # user packages
        packages = with pkgs; [
          vlc
          eza
          btop
          kitty
          brave
          satty
          fuzzel
          firefox
          equibop
          hyprshot
          grimblast
          superfile
          librewolf
          fastfetch
          zed-editor
          evil-helix
          prismlauncher
          ayugram-desktop
          inputs.walker.packages.${system}.default
          inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default
        ];
      };
    };
}
