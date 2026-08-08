{ lib, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      checks.axiom = pkgs.runCommandLocal "axiom-tests" { } (
        assert (import ../_lib/axiom/tests/default.nix { inherit lib; }).ok;
        "touch $out"
      );
    };
}
