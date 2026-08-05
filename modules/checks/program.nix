{ lib, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      tests = import ../_lib/program-tests.nix { inherit lib pkgs; };
    in
    {
      checks.program-boundary = pkgs.runCommandLocal "program-boundary-tests" { } (
        assert tests.ok;
        "touch $out"
      );
    };
}
