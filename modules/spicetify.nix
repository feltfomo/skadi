{ inputs, ... }:
{
  flake.nixosModules.spicetify =
    { ... }:
    let
      spicePkgs = inputs.spicetify-nix.legacyPackages.x86_64-linux;
    in
    {
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
