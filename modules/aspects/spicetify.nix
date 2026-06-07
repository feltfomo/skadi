{
  inputs,
  rootPath,
  ...
}:
{
  den.aspects.spicetify.homeManager =
    { pkgs, ... }:
    let
      spicePkgs = inputs.spicetify-nix.legacyPackages.${pkgs.stdenv.hostPlatform.system};
      lucid = pkgs.callPackage "${rootPath}/modules/_pkgs/lucid.nix" { };
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
