{ pkgs, inputs, ... }:
{
  imports = [
    ./home/fish.nix
    ./home/spicetify.nix
    inputs.spicetify-nix.homeManagerModules.spicetify
  ];
  home.username = "feltfomo";
  home.homeDirectory = "/home/feltfomo";

  home.packages = with pkgs; [
    firefox
    librewolf
  ];

  programs.git.settings = {
    enable = true;
    userName = "feltfomo";
    userEmail = "241195017+feltfomo@users.noreply.github.com";
  };

  home.stateVersion = "25.11";
}
