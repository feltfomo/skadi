{
  inputs,
  rootPath,
  ...
}:
{
  flake-file.inputs = {
    spicetify-nix = {
      url = "github:Gerg-L/spicetify-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    spicetify-lucid = {
      url = "gitlab:sanoojes/spicetify-lucid?ref=main";
      flake = false;
    };
  };

  den.aspects.spicetify.homeManager =
    { pkgs, ... }:
    let
      spicePkgs = inputs.spicetify-nix.legacyPackages.${pkgs.stdenv.hostPlatform.system};
      lucid = pkgs.callPackage "${rootPath}/pkgs/lucid" {
        src = inputs.spicetify-lucid;
      };
    in
    {
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
}
