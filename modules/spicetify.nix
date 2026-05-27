{ inputs, ... }:
{
  flake.modules.nixos.spicetify =
    { pkgs, ... }:
    let
      spicePkgs = inputs.spicetify-nix.legacyPackages.x86_64-linux;
      lucid = pkgs.callPackage ./_pkgs/lucid.nix { };
    in
    {
      home-manager.users.feltfomo = {
        imports = [ inputs.spicetify-nix.homeManagerModules.default ];
        programs.spicetify = {
          enable = true;
          theme = {
            name = "Lucid";
            src = lucid;
            injectCss = true;
            injectThemeJs = true;
            replaceColors = false;
            overwriteAssets = true;
          };
          colorScheme = "dark";
          enabledExtensions = with spicePkgs.extensions; [
            shuffle
            fullAppDisplay
            beautifulLyrics
            adblockify
            hidePodcasts
            simpleBeautifulLyrics
            spicyLyrics
          ];
        };
      };
    };
}
