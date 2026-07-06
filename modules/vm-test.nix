# Packages scripts/vm-test.sh as `nix run .#vm-test`. The bash is kept in its
# own file instead of inlined so it stays readable and syncs cleanly. The one
# thing nix does that the script can't is resolve the OVMF firmware path at
# build time and pass it in as OVMF_FD. runtimeInputs deliberately omits nix so
# the ISO build uses the caller's Lix and the Lix-dialect flake.lock evaluates.
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
          # resolved here so the script doesn't have to hunt for OVMF
          OVMF_FD='${pkgs.OVMF.fd}'
          export OVMF_FD
        ''
        + builtins.readFile ../scripts/vm-test.sh;
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
