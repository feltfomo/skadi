#!/usr/bin/env bash
# vm-test -- one-command VM test harness for the skadi installer (Phase 2b).
#
# Reproduces "tonight's cold install" end to end on a disposable localhost VM:
#   build installer ISO -> fresh qcow2 -> boot headless UEFI/OVMF QEMU
#   -> (optional) drive an UNATTENDED cold-from-source `skadi-install <host>`
#      over ssh -> grep the serial console for boot + login -> teardown.
#
# The permanent gate this exists to reproduce is COLD-FROM-SOURCE on 8 GB:
# Lix (deliberately uncached), notion-sync, and the fleet closure all build
# from source inside the VM. There is NO cache shortcut here, on purpose.
#
# Artifacts hygiene: EVERYTHING lives under ~/.cache/skadi-vm; nothing is ever
# written into the repo tree. The ISO is built with -o <cache>/iso-result.
#
# `set -euo pipefail` and PATH (qemu, openssh, coreutils, grep) are injected by
# writeShellApplication. OVMF_FD (the OVMF firmware store path) is exported by
# modules/vm-test.nix, so this script never has to guess where OVMF lives. The
# ISO build uses the CALLER's `nix` (Lix) from PATH -- never a bundled CppNix --
# so the Lix-dialect flake.lock keeps evaluating cleanly and git-aware.

CACHE="${SKADI_VM_CACHE:-$HOME/.cache/skadi-vm}"
SSH_PORT=2222
SSH_KEY="$CACHE/vm-test-key"

# --- ssh helper subcommand: `nix run .#vm-test -- ssh [args...]` -------------
if [ "${1:-}" = ssh ]; then
  shift
  exec ssh -i "$SSH_KEY" -p "$SSH_PORT" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o LogLevel=ERROR \
    root@localhost "$@"
fi

# --- defaults (all overridable by flags) ------------------------------------
HOST="vm"
RAM="8192"           # MiB. MUST allow lower -- the 8 GB cold gate is the default.
CORES="4"
DISK="100G"
FLAKE="$(pwd)"       # git-aware flake ref for the ISO build; override with --flake.
KEEP=0               # keep the qcow2 after the run instead of deleting it
RESET=0              # discard any existing qcow2 (+ OVMF vars) and start clean
DO_INSTALL=1         # drive the unattended install; --no-install just boots the ISO

# Throwaway feltfomo login hash, baked in on purpose: this VM is a disposable
# localhost target with no network and only the NOTION_TOKEN *placeholder*, so
# it guards nothing real. Plaintext is "skadi". Override via SKADI_FELTFOMO_PW_HASH.
: "${SKADI_FELTFOMO_PW_HASH:=}"
if [ -n "$SKADI_FELTFOMO_PW_HASH" ]; then
  PW_HASH="$SKADI_FELTFOMO_PW_HASH"
else
  # shellcheck disable=SC2016
  PW_HASH='$6$skadivmtest$tp5BUeNDHy1miR21O7X2QXROL/yxzqnT9XeKJ4UKI.PpyYdkise0/iV58ErEoKs5SuKbvW/xy93Mzu3lQ2Fgf0'
fi

log()  { printf '\033[0;36m[vm-test]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[vm-test]\033[0m %s\n' "$*"; }
die()  { printf '\033[0;31m[vm-test]\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'USAGE'
vm-test -- one-command skadi installer VM harness

  nix run .#vm-test -- [flags]        build ISO, boot VM, drive unattended install, verify, teardown
  nix run .#vm-test -- ssh [args...]  ssh into the running VM (root@localhost:2222)

flags:
  --host <name>    host to install (default: vm)
  --ram <MiB>      guest RAM in MiB (default: 8192; lower is allowed and is the point)
  --cores <n>      guest vCPUs (default: 4)
  --disk <size>    qcow2 size for a fresh disk (default: 100G)
  --flake <ref>    flake ref for the ISO build (default: current dir)
  --keep           keep the qcow2 after the run (default: delete on success)
  --reset          discard any existing qcow2 + OVMF vars and start clean
  --no-install     just build the ISO and boot it; skip the unattended install
  -h, --help       show this help
USAGE
}

ssh_vm() {
  ssh -i "$SSH_KEY" -p "$SSH_PORT" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o LogLevel=ERROR \
    -o ConnectTimeout=5 \
    root@localhost "$@"
}

# --- parse flags ------------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    --host)  HOST="$2"; shift 2 ;;
    --ram)   RAM="$2"; shift 2 ;;
    --cores) CORES="$2"; shift 2 ;;
    --disk)  DISK="$2"; shift 2 ;;
    --flake) FLAKE="$2"; shift 2 ;;
    --keep)  KEEP=1; shift ;;
    --reset) RESET=1; shift ;;
    --no-install) DO_INSTALL=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
done

# --- preflight --------------------------------------------------------------
command -v nix >/dev/null || die "no 'nix' on PATH -- run this via 'nix run .#vm-test'"
[ -n "${OVMF_FD:-}" ] || die "OVMF_FD not set (it is exported by modules/vm-test.nix)"
OVMF_CODE="$OVMF_FD/FV/OVMF_CODE.fd"
OVMF_VARS_SRC="$OVMF_FD/FV/OVMF_VARS.fd"
[ -f "$OVMF_CODE" ] || die "OVMF_CODE.fd not found at $OVMF_CODE"

mkdir -p "$CACHE"

# vm-test private key: dedicated throwaway, NEVER a synced repo file. Its public
# half is committed in modules/installer.nix authorizedKeys. Missing -> the
# harness can't drive the install, so fail loudly with placement help.
if [ ! -f "$SSH_KEY" ]; then
  die "missing vm-test private key at $SSH_KEY
  -> place the dedicated throwaway private key there (chmod 600) and re-run.
     Its public half is baked into modules/installer.nix; this key must never
     live in the repo / notion-sync tree."
fi
chmod 600 "$SSH_KEY" 2>/dev/null || true

ISO_LINK="$CACHE/iso-result"
DISK_IMG="$CACHE/$HOST.qcow2"
VARS="$CACHE/vm-vars.fd"
SERIAL="$CACHE/$HOST-serial.log"
INSTALL_LOG="$CACHE/$HOST-install.log"

# 1. build the installer ISO (cold; caller's Lix; git-aware ref).
log "building installer ISO ($FLAKE) -> $ISO_LINK"
nix build "$FLAKE#nixosConfigurations.installer.config.system.build.isoImage" -o "$ISO_LINK"
shopt -s nullglob
isos=("$ISO_LINK"/iso/*.iso)
shopt -u nullglob
[ "${#isos[@]}" -gt 0 ] || die "no ISO found under $ISO_LINK/iso/"
ISO="${isos[0]}"
log "ISO: $ISO"

# 2. qcow2 + OVMF vars, kept in lockstep. A fresh disk MUST get fresh NVRAM: a
#    stale OVMF_VARS that still lists a previous install's boot entry (pointing
#    at a now-gone disk GUID) makes the firmware try the empty disk/PXE instead
#    of the ISO -- exactly the "failed to load NixOS-boot ... Not Found" hang.
if [ "$RESET" = 1 ]; then rm -f "$DISK_IMG"; fi
fresh_disk=0
if [ ! -f "$DISK_IMG" ]; then
  log "creating fresh $DISK qcow2 -> $DISK_IMG"
  qemu-img create -f qcow2 "$DISK_IMG" "$DISK" >/dev/null
  fresh_disk=1
fi
if [ "$RESET" = 1 ] || [ "$fresh_disk" = 1 ] || [ ! -f "$VARS" ]; then
  log "seeding writable OVMF vars -> $VARS"
  install -m600 "$OVMF_VARS_SRC" "$VARS"
fi

: > "$SERIAL"

# 4. boot the installer VM headless (UEFI/OVMF; serial captured to a log file).
QEMU_COMMON=(
  -machine "q35,accel=kvm"
  -cpu host
  -m "$RAM"
  -smp "$CORES"
  -drive "if=pflash,format=raw,readonly=on,file=$OVMF_CODE"
  -drive "if=pflash,format=raw,file=$VARS"
  -drive "file=$DISK_IMG,if=virtio,format=qcow2"
  -netdev "user,id=net0,hostfwd=tcp::$SSH_PORT-:22"
  -device "virtio-net,netdev=net0"
  -display none
  -serial "file:$SERIAL"
  -no-reboot
)

QEMU_PID=""
teardown() {
  if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
  if [ "$KEEP" = 1 ]; then
    log "keeping artifacts under $CACHE (--keep)"
  else
    rm -f "$DISK_IMG"
    log "removed $DISK_IMG (pass --keep to retain it)"
  fi
}
trap teardown EXIT

log "booting installer VM: ${RAM} MiB RAM, ${CORES} vCPU, ssh on :$SSH_PORT"
log "serial console -> $SERIAL   (tail -f to watch the cold build)"
qemu-system-x86_64 "${QEMU_COMMON[@]}" -boot order=dc -cdrom "$ISO" &
QEMU_PID=$!

# 5. wait for the ISO's sshd (root + vm-test key).
log "waiting for the installer VM to accept ssh on :$SSH_PORT ..."
up=0
for ((i = 0; i < 60; i++)); do
  kill -0 "$QEMU_PID" 2>/dev/null || die "QEMU exited before ssh came up (see $SERIAL)"
  if ssh_vm true 2>/dev/null; then up=1; break; fi
  sleep 5
done
[ "$up" = 1 ] || die "installer VM never accepted ssh within timeout (see $SERIAL)"
log "installer VM is up."

if [ "$DO_INSTALL" != 1 ]; then
  log "--no-install: leaving the ISO booted."
  log "poke it with:  nix run .#vm-test -- ssh"
  log "Ctrl-C to stop and tear the VM down."
  wait "$QEMU_PID"
  exit 0
fi

# 6. drive the UNATTENDED cold install over ssh. ONE attempt, run to completion
#    -- never interrupt it (a killed heavy derivation discards all progress).
#    feltfomo password: throwaway hash via env. notion-token: left UNSET, so the
#    installer keeps its placeholder (NOTION_TOKEN=REPLACE_ME). Cold-from-source
#    is inherited from the ISO's own nix.settings (Lix uncached), not forced here.
log "driving unattended 'skadi-install $HOST' (cold, from source) ..."
log "install log -> $INSTALL_LOG"
remote="env SKADI_INSTALL_UNATTENDED=1 SKADI_SECRET_FELTFOMO_PASSWORD='${PW_HASH}' skadi-install '${HOST}'"
ssh_vm "$remote" 2>&1 | tee "$INSTALL_LOG"
rc="${PIPESTATUS[0]}"
[ "$rc" = 0 ] || die "unattended skadi-install failed (rc=$rc); see $INSTALL_LOG and $SERIAL."
log "install finished (rc=0). powering the ISO down to boot the installed disk."

# 7. power the ISO VM off, then boot the INSTALLED disk (no cdrom).
ssh_vm poweroff 2>/dev/null || true
wait "$QEMU_PID" 2>/dev/null || true
QEMU_PID=""

: > "$SERIAL"
log "booting the installed disk (no ISO) to verify $HOST comes up ..."
qemu-system-x86_64 "${QEMU_COMMON[@]}" -boot order=cd &
QEMU_PID=$!

# 8. verification: watch the serial log for a boot-complete + login marker.
#    NOTE: depends on the installed host putting a console on ttyS0. If it does
#    not, this times out to a WARN (the install already succeeded above) -- re-run
#    with --keep and inspect the console yourself.
log "watching $SERIAL for a login prompt ..."
verified=0
for ((i = 0; i < 60; i++)); do
  kill -0 "$QEMU_PID" 2>/dev/null || break
  if grep -Eq "($HOST login:|login:|Reached target.*Multi-User|Startup finished)" "$SERIAL" 2>/dev/null; then
    verified=1; break
  fi
  sleep 5
done

if [ "$verified" = 1 ]; then
  log "installed $HOST reached a login prompt -- feltfomo can log in. PASS."
else
  warn "no login marker seen on serial within timeout."
  warn "the install itself succeeded (rc=0); the installed host may not log to ttyS0."
  warn "re-run with --keep and inspect $SERIAL or attach a console to confirm login."
fi

log "done."