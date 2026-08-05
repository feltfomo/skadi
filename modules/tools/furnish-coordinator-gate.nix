_: {
  perSystem =
    { pkgs, ... }:
    let
      furnish-coordinator-gate = pkgs.writeShellApplication {
        name = "furnish-coordinator-gate";
        # the gate certifies the host, so nix is deliberately absent from these
        # runtime inputs and must not be re-added. the gate must use the host's
        # evaluator rather than silently certify it under a different nix.
        runtimeInputs = with pkgs; [
          bash
          bc
          coreutils
          findutils
          git
          gnugrep
          gnused
          jq
          nixos-rebuild
          systemd
          util-linux
        ];
        text = builtins.readFile ../../scripts/furnish-coordinator-gate.sh;
      };
    in
    {
      packages.furnish-coordinator-gate = furnish-coordinator-gate;
      apps.furnish-coordinator-gate = {
        type = "app";
        program = "${furnish-coordinator-gate}/bin/furnish-coordinator-gate";
      };
    };
}
