# perSystem check that forces the pure ownerships engine's own test suite.
# Nothing consumes the engine yet, so nothing else evaluates it -- without this,
# `nix flake check` would be green on the engine vacuously. This runs
# compose/check/select/merge, the three outcomes, a throwaway third axis, an
# opt-in merge strategy, and the top identity law.
{ lib, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      checks.ownerships-engine = pkgs.runCommandLocal "ownerships-engine-tests" { } (
        assert (import ./_lib/ownerships/tests.nix { inherit lib; }).ok;
        "touch $out"
      );
    };
}
