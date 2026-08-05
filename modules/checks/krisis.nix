{ lib, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      checks.krisis = pkgs.runCommandLocal "krisis-tests" { } (
        assert (import ../_lib/krisis/tests/default.nix { inherit lib; }).ok;
        "touch $out"
      );
    };
}
