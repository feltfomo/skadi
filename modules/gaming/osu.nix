{
  den.aspects.osu.homeManager =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.osu-lazer-bin ];
    };
}
