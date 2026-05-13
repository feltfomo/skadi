{
  pkgs,
  inputs,
  system,
  ...
}:
{
  imports = [
    ./home/walker.nix
    ./home/spicetify.nix
    ./home/nix-your-shell.nix
    inputs.spicetify-nix.homeManagerModules.spicetify
    inputs.walker.homeManagerModules.default
  ];

  home = {
    username = "feltfomo";
    homeDirectory = "/home/feltfomo";
    stateVersion = "25.11";

    packages = with pkgs; [
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
      inputs.noctalia.packages.${system}.default
      inputs.walker.packages.${system}.default
    ];
  };
}
