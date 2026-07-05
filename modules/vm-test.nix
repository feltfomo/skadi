# One-command VM test harness for the skadi installer (Phase 2b).
#
#   nix run .#vm-test -- --host vm
#
# Builds the installer ISO, boots a headless UEFI/OVMF QEMU VM, drives an
# UNATTENDED cold-from-source `skadi-install <host>` over ssh, greps the serial
# console to confirm the installed host boots to a login prompt, then tears the
# VM down. Every artifact lives under ~/.cache/skadi-vm; nothing touches the repo.
#
# The bash lives in scripts/vm-test.sh and is readFile'd in here -- mirroring how
# modules/installer.nix bakes scripts/skadi-install.sh -- so it stays editable,
# testable, and cleanly synced by notion-sync (do NOT inline it).
#
# OVMF's firmware store path is resolved at build time and exported as OVMF_FD,
# so the harness auto-resolves OVMF instead of guessing. The ISO build itself
# uses the CALLER's `nix` (Lix) from PATH -- deliberately NOT a bundled nix in
# runtimeInputs -- so the Lix-dialect flake.lock keeps evaluating git-aware.
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
          # OVMF firmware path, resolved at build time (auto-resolve; no guessing).
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
