{ inputs, pkgs, ... }:
let
  spicePkgs = inputs.spicetify-nix.legacyPackages.${pkgs.stdenv.system};
in
{
  programs.spicetify = {
    enable = true;
    theme = spicePkgs.themes.bloom;
    colorScheme = "";
    enabledExtensions = with spicePkgs.extensions; [
      shuffle
      fullAppDisplay
      beautifulLyrics
      adblockify
      hidePodcasts
    ];
  };
}
