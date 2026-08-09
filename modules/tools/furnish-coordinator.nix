{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      # built from this config's pkgs rather than taken as a package output, so the
      # binary behind this app is the same store path the reconcile unit runs.
      furnish-coordinator = inputs.lexicon.lib.mkCoordinator { inherit pkgs; };

      # the host fault proofs crash the binary at named durability points, which
      # only the fault-injection feature compiles in.
      furnish-coordinator-fault-injection = inputs.lexicon.lib.mkCoordinator {
        inherit pkgs;
        suffix = "-fault-injection";
        features = [ "fault-injection" ];
      };
    in
    {
      packages = { inherit furnish-coordinator furnish-coordinator-fault-injection; };
      apps.furnish-coordinator = {
        type = "app";
        program = "${furnish-coordinator}/bin/furnish-coordinator";
      };
    };
}
