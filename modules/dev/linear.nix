{
  den.aspects.linear.homeManager =
    { pkgs, lib, ... }:
    let
      icon = pkgs.fetchurl {
        name = "linear-icon-512.png";
        url = "https://static.linear.app/assets/pwa/icon_512.png?v=3";
        hash = "sha256-26KMWuUYHMZa7+NANh1Xud52UrWFT4pF8eBwHlNr/FQ=";
      };
    in
    {
      xdg.desktopEntries.linear = {
        name = "Linear";
        genericName = "Issue tracker";
        exec = "${lib.getExe pkgs.brave-origin} --class=linear --app=https://linear.app/login";
        inherit icon;
        terminal = false;
        categories = [ "Office" ];
        settings.StartupWMClass = "linear";
      };
    };
}
