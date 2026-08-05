_: {
  # keep the harness at perSystem scope so adding it cannot alter a host closure.
  perSystem =
    { pkgs, ... }:
    let
      program-files-regression = pkgs.writeShellApplication {
        name = "program-files-regression";
        runtimeInputs = with pkgs; [
          coreutils
          gnugrep
          gnused
          gawk
          git
          gnutar
          jq
          util-linux
          openssh
          ssh-to-age
          sops
          qemu_kvm
        ];
        text = ''
          # Use the caller's lix; only immutable fixture inputs are baked into the wrapper.
          OVMF_FD='${pkgs.OVMF.fd}'
          PROGRAM_FILES_MANIFEST='${../../tests/program-files-manifest.json}'
          PROGRAM_FILES_BASELINE='${../../tests/program-files-baseline.json}'
          export OVMF_FD PROGRAM_FILES_MANIFEST PROGRAM_FILES_BASELINE
        ''
        + builtins.readFile ../../scripts/program-files-regression.sh;
      };
    in
    {
      packages.program-files-regression = program-files-regression;
      apps.program-files-regression = {
        type = "app";
        program = "${program-files-regression}/bin/program-files-regression";
      };
    };
}
