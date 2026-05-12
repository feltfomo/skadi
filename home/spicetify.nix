{ spicePkgs, ... }:
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
