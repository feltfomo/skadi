{ lexicon, ... }:
{
  den.aspects.appimage = lexicon {
    package = pkgs: pkgs.appimage-run;
  };
}
