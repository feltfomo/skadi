# perSystem checks that force the pure ownerships suites. Nothing consumes the
# engine yet, so without these `nix flake check` would be green on it vacuously.
# The engine suite runs compose/check/select/merge, the three outcomes, a
# throwaway third axis, an opt-in merge strategy, and the top identity law. The
# roster suite proves the den-free define.* backend and the host<->user
# membership check resolve with no den in scope. The surface suite resolves a
# throwaway aspect through the public authoring surface across every claim kind
# and checks that a misshaped ownership key fails loudly.
{ lib, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      checks.ownerships-engine = pkgs.runCommandLocal "ownerships-engine-tests" { } (
        assert (import ../_lib/ownerships/tests/engine.nix { inherit lib; }).ok;
        "touch $out"
      );
      checks.ownerships-roster = pkgs.runCommandLocal "ownerships-roster-tests" { } (
        assert (import ../_lib/ownerships/tests/roster.nix { inherit lib; }).ok;
        "touch $out"
      );
      checks.ownerships-surface = pkgs.runCommandLocal "ownerships-surface-tests" { } (
        assert (import ../_lib/ownerships/tests/surface.nix { inherit lib; }).ok;
        "touch $out"
      );
      checks.ownerships-descriptors = pkgs.runCommandLocal "ownerships-descriptor-tests" { } (
        assert (import ../_lib/ownerships/tests/descriptors.nix { inherit lib; }).ok;
        "touch $out"
      );
      checks.ownerships-matrix = pkgs.runCommandLocal "ownerships-matrix-tests" { } (
        assert (import ../_lib/ownerships/tests/matrix.nix { inherit lib; }).ok;
        "touch $out"
      );
    };
}
