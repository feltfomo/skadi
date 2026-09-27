# runtimeInputs omits nix so the iso build uses the caller's lix.
_: {
  perSystem =
    { pkgs, ... }:
    let
      vm-test = pkgs.writeShellApplication {
        name = "vm-test";
        runtimeInputs = with pkgs; [
          qemu_kvm
          coreutils
          openssh
          gnugrep
        ];
        text = ''
          OVMF_FD='${pkgs.OVMF.fd}'
          export OVMF_FD
        ''
        + builtins.readFile ../../tests/vm-test.sh;
      };
    in
    {
      packages.vm-test = vm-test;
      apps.vm-test = {
        type = "app";
        program = "${vm-test}/bin/vm-test";
      };
    };
}
