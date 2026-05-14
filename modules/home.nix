{ inputs, ... }:
{
  flake.nixosModules.home =
    { pkgs, ... }:
    {
      home-manager.users.feltfomo = {
        home = {
          # set username
          username = "feltfomo";

          # tell home dir
          homeDirectory = "/home/feltfomo";

          # set state version
          stateVersion = "25.11";

          # user packages
          packages = with pkgs; [
            vlc
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
            prismlauncher
            ayugram-desktop
            inputs.walker.packages.${system}.default
            inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default
          ];
        };
      };
    };
}
