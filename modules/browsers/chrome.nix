{
  den.aspects.chrome.homeManager =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.google-chrome ];
      home.sessionVariables.BROWSER = "google-chrome-stable";
    };
}
