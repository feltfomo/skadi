# perSystem checks that force the pure ownerships suites. Nothing consumes the
# engine yet, so without these `nix flake check` would be green on it vacuously.
# The engine suite runs compose/check/select/merge, the three outcomes, a
# throwaway third axis, an opt-in merge strategy, and the top identity law. The
# roster suite proves the den-free define.* backend and the host<->user
# membership check resolve with no den in scope.
{ lib, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      checks.ownerships-engine = pkgs.runCommandLocal "ownerships-engine-tests" { } (
        assert (import ./_lib/ownerships/tests.nix { inherit lib; }).ok;
        "touch $out"
      );
      checks.ownerships-roster = pkgs.runCommandLocal "ownerships-roster-tests" { } (
        assert (import ./_lib/ownerships/roster-tests.nix { inherit lib; }).ok;
        "touch $out"
      );
    };
}
