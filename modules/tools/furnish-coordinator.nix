{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      # built from this config's pkgs rather than taken as a package output, so the
      # binary behind this app is the same store path the reconcile unit runs.
      furnish-coordinator = inputs.lexicon.lib.mkCoordinator { inherit pkgs; };
    in
    {
      packages.furnish-coordinator = furnish-coordinator;
      apps.furnish-coordinator = {
        type = "app";
        program = "${furnish-coordinator}/bin/furnish-coordinator";
      };
    };
}
