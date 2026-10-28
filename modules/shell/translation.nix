{ lexicon, ... }:
{
  den.aspects.translation = lexicon {
    package = pkgs: pkgs.translate-shell;
  };
}
