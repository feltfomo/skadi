_: {
  perSystem =
    { pkgs, ... }:
    let
      furnish-coordinator-gate = pkgs.writeShellApplication {
        name = "furnish-coordinator-gate";
        runtimeInputs = with pkgs; [
          bash
          bc
          coreutils
          findutils
          git
          gnugrep
          gnused
          jq
          nix
          nixos-rebuild
          systemd
          util-linux
        ];
        text = builtins.readFile ../scripts/furnish-coordinator-gate.sh;
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
