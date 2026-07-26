_: {
  perSystem =
    { pkgs, ... }:
    let
      furnish-coordinator = import ./_lib/furnish/coordinator.nix { inherit pkgs; };
    in
    {
      packages.furnish-coordinator = furnish-coordinator;
      apps.furnish-coordinator = {
        type = "app";
        program = "${furnish-coordinator}/bin/furnish-coordinator";
      };
    };
}
