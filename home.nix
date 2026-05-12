{ pkgs, inputs, ... }:
{
  imports = [
    ./home/git.nix
    ./home/fish.nix
    ./home/fuzzel.nix
    ./home/walker.nix
    ./home/spicetify.nix
    ./home/nix-your-shell.nix
    inputs.spicetify-nix.homeManagerModules.spicetify
    inputs.walker.homeManagerModules.default
  ];

  home.username = "feltfomo";
  home.homeDirectory = "/home/feltfomo";

  home.packages = with pkgs; [
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
    inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default
    inputs.walker.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];

  home.stateVersion = "25.11";
}
