{ pkgs, inputs, ... }:
{
  imports = [
    ./home/git.nix
    ./home/fish.nix
    ./home/fuzzel.nix
    ./home/walker.nix
    ./home/spicetify.nix
    inputs.spicetify-nix.homeManagerModules.spicetify
    inputs.walker.homeManagerModules.default
  ];

  home.username = "feltfomo";
  home.homeDirectory = "/home/feltfomo";

  home.packages = with pkgs; [
    kitty
    brave
    fuzzel
    firefox
    equibop
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
