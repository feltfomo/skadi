# packages tests/vm-test.sh as `nix run .#vm-test`. the bash lives in its own
# file so it stays readable and syncs cleanly. nix resolves the ovmf firmware path
# at build time and passes it in as OVMF_FD. runtimeInputs omits nix so the iso
# build uses the caller's lix and the lix-dialect flake.lock evaluates.
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
          # resolved here so the script doesn't have to hunt for ovmf
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
