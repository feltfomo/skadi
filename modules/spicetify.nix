{ inputs, ... }:
{
  flake.nixosModules.spicetify =
    { ... }:
    # define spicePkgs
    let
      spicePkgs = inputs.spicetify-nix.legacyPackages.x86_64-linux;
    in
    {
      # set theme and extensions for feltfomo on spicetify
      home-manager.users.feltfomo = {
        imports = [ inputs.spicetify-nix.homeManagerModules.default ];
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
      };
    };
}
