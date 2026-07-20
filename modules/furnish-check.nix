{
  lib,
  resolve,
  resolveSystem,
  ...
}:
{
  perSystem =
    { pkgs, ... }:
    {
      checks.furnish-pure = pkgs.runCommandLocal "furnish-pure-tests" { } (
        assert
          (import ./_lib/furnish/tests.nix {
            inherit
              lib
              resolve
              resolveSystem
              ;
          }).ok;
        "touch $out"
      );
    };
}
