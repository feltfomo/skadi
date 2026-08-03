{
  program,
  ...
}:
{
  den.aspects.ghostty = program {
    pkg = pkgs: pkgs.ghostty;
  };
}
