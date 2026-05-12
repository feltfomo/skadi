{ pkgs, inputs, ... }:
{
  imports = [
    ./home/git.nix
    ./home/fish.nix
    ./home/fuzzel.nix
    ./home/spicetify.nix
    inputs.spicetify-nix.homeManagerModules.spicetify
  ];

  home.username = "feltfomo";
  home.homeDirectory = "/home/feltfomo";

  home.packages = with pkgs; [
    kitty
    brave
    fuzzel
    firefox
    equibop
    librewolf
    fastfetch
    zed-editor
    prismlauncher
    inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];

  home.stateVersion = "25.11";
}
