_: {
  perSystem =
    { pkgs, ... }:
    let
      furnish-coordinator = pkgs.rustPlatform.buildRustPackage {
        pname = "furnish-coordinator";
        version = "0.1.0";
        src = ./_lib/furnish/coordinator;
        cargoLock.lockFile = ./_lib/furnish/coordinator/Cargo.lock;
      };
    in
    {
      packages.furnish-coordinator = furnish-coordinator;
      apps.furnish-coordinator = {
        type = "app";
        program = "${furnish-coordinator}/bin/furnish-coordinator";
      };
    };
}
