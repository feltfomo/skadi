#!/usr/bin/env bash
# build the installer iso, boot it in a throwaway localhost vm, optionally run an
# unattended skadi-install, and confirm the result boots to a login prompt.
# everything lives under ~/.cache/skadi-vm; the repo tree is never touched.
#
# the install runs cold on purpose: lix and notion-sync are uncached, so this
# exercises the real worst case (a from-source build on a small box).
#
# set -euo pipefail and PATH come from writeShellApplication. OVMF_FD comes from
# the nix wrapper. the iso build reuses the caller's lix so the lix-dialect
# flake.lock still evaluates.

CACHE="${SKADI_VM_CACHE:-$HOME/.cache/skadi-vm}"
SSH_PORT=2222
SSH_KEY="$CACHE/vm-test-key"

# ssh subcommand: shell into the running vm
if [ "${1:-}" = ssh ]; then
  shift
  exec ssh -i "$SSH_KEY" -p "$SSH_PORT" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o LogLevel=ERROR \
    root@localhost "$@"
fi

HOST="vm"
RAM="8192"           # MiB; keep it low, the small-RAM cold build is the point
CORES="4"
DISK="100G"
FLAKE="$(pwd)"
KEEP=0
RESET=0
DO_INSTALL=1
DROP=""              # comma/space list of top-level aspects to drop (composed install)

# the vm has no network and only a placeholder token, so this login hash guards
# nothing. plaintext is "skadi". override with SKADI_FELTFOMO_PW_HASH.
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
  --drop <a,b,c>   drop top-level aspects from the host (composed install via mkInstallTarget)
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
    --drop)  DROP="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
done

command -v nix >/dev/null || die "no 'nix' on PATH -- run this via 'nix run .#vm-test'"
[ -n "${OVMF_FD:-}" ] || die "OVMF_FD not set (should come from the nix wrapper)"
OVMF_CODE="$OVMF_FD/FV/OVMF_CODE.fd"
OVMF_VARS_SRC="$OVMF_FD/FV/OVMF_VARS.fd"
[ -f "$OVMF_CODE" ] || die "OVMF_CODE.fd not found at $OVMF_CODE"

mkdir -p "$CACHE"

# dedicated throwaway key, never committed. its public half is in the installer's
# authorizedKeys; without it we can't drive the install, so fail loudly.
if [ ! -f "$SSH_KEY" ]; then
  die "missing vm-test private key at $SSH_KEY
  -> place the dedicated throwaway private key there (chmod 600) and re-run.
     Its public half is in the installer's authorizedKeys; this key must never
     live in the repo / notion-sync tree."
fi
chmod 600 "$SSH_KEY" 2>/dev/null || true

ISO_LINK="$CACHE/iso-result"
DISK_IMG="$CACHE/$HOST.qcow2"
VARS="$CACHE/vm-vars.fd"
SERIAL="$CACHE/$HOST-serial.log"
INSTALL_LOG="$CACHE/$HOST-install.log"

log "building installer ISO ($FLAKE) -> $ISO_LINK"
nix build "$FLAKE#nixosConfigurations.installer.config.system.build.isoImage" -o "$ISO_LINK"
shopt -s nullglob
isos=("$ISO_LINK"/iso/*.iso)
shopt -u nullglob
[ "${#isos[@]}" -gt 0 ] || die "no ISO found under $ISO_LINK/iso/"
ISO="${isos[0]}"
log "ISO: $ISO"

# fresh disk needs fresh nvram. a stale OVMF_VARS still listing a previous
# install's boot entry (pointing at a gone disk guid) makes the firmware try the
# empty disk or pxe instead of the iso: the "failed to load NixOS-boot / Not
# Found" hang.
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

# headless uefi boot; serial is captured to a log file
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

# one attempt, run to completion; killing a heavy derivation throws away its
# progress. the token is left unset so the installer keeps its placeholder, and
# cold-from-source comes from the iso's own nix settings, not from here.
log "driving unattended 'skadi-install $HOST' (cold, from source) ..."
log "install log -> $INSTALL_LOG"
# IN_DISKO_TEST=1 is disko's own hook: its luks script keys the cryptroot slot
# with the deterministic passphrase `disko` (--key-file <(echo -n ..), no trailing
# newline) instead of prompting on a tty we don't have. the installed vm host
# embeds a byte-identical keyfile in its initrd, so the disk auto-unlocks on the
# post-install boot and the harness can watch for a login prompt. vm-only: real
# skadi-install runs never set it, so khion keeps its passphrase.
# feed every mkpasswd secret on this host the deterministic test hash, derived
# from the host's own config, so generic gets owner-password, khion gets
# feltfomo-password, and any future host gets whatever it declares. only
# method == "mkpasswd" secrets are forced; paste/optional ones self-placeholder
# when unset. env var names match skadi-install: SKADI_SECRET_<NAME>, uppercased,
# '-' -> '_'. evaluated against $FLAKE; a --drop run's secret set is only ever a
# subset, so any extra env var is ignored.
log "resolving mkpasswd secrets for '$HOST' from its config"
mkpasswd_secrets="$(nix eval --raw "${FLAKE}#nixosConfigurations.${HOST}.config.skadi.provision.secrets" \
  --apply 's: builtins.concatStringsSep "\n" (builtins.filter (n: (builtins.getAttr n s).method == "mkpasswd") (builtins.attrNames s))')" \
  || die "could not read skadi.provision.secrets for '$HOST' (nix eval failed)"
SECRET_ENV=""
while IFS= read -r secret; do
  [ -n "$secret" ] || continue
  envvar="SKADI_SECRET_$(printf '%s' "$secret" | tr 'a-z-' 'A-Z_')"
  # single-quote the hash so the remote shell doesn't expand the $6$... in it.
  # shellcheck disable=SC2089
  SECRET_ENV="$SECRET_ENV $envvar='${PW_HASH}'"
  log "  $secret -> $envvar"
done <<SECRETS
$mkpasswd_secrets
SECRETS
# No identity directory is supplied here: skadi-install creates the standalone
# test's disposable host identity and encrypted fixture inside its throwaway clone.
# shellcheck disable=SC2090
remote="env IN_DISKO_TEST=1 SKADI_INSTALL_UNATTENDED=1${SECRET_ENV} skadi-install '${HOST}'"
if [ -n "$DROP" ]; then
  remote="$remote --drop '${DROP}'"
  log "composed install: dropping top-level aspect(s): $DROP"
fi
ssh_vm "$remote" 2>&1 | tee "$INSTALL_LOG"
rc="${PIPESTATUS[0]}"
[ "$rc" = 0 ] || die "unattended skadi-install failed (rc=$rc); see $INSTALL_LOG and $SERIAL."
log "install finished (rc=0). powering the ISO down to boot the installed disk."

ssh_vm poweroff 2>/dev/null || true
wait "$QEMU_PID" 2>/dev/null || true
QEMU_PID=""

: > "$SERIAL"
log "booting the installed disk (no ISO) to verify $HOST comes up ..."
qemu-system-x86_64 "${QEMU_COMMON[@]}" -boot order=cd &
QEMU_PID=$!

# Serial markers are diagnostic only: a console can be quiet while the system is
# healthy, and a login prompt can appear before required services settle. Prove
# the installed system over its test-only SSH identity, then require systemd to
# reach a non-degraded running state.
log "waiting for the installed $HOST to accept ssh on :$SSH_PORT ..."
installed_ssh=0
for ((i = 0; i < 120; i++)); do
  kill -0 "$QEMU_PID" 2>/dev/null || die "installed VM exited before ssh came up (see $SERIAL)"
  if ssh_vm true 2>/dev/null; then installed_ssh=1; break; fi
  sleep 5
done
[ "$installed_ssh" = 1 ] || die "installed VM never accepted ssh within 10 minutes (see $SERIAL)"
log "installed $HOST accepts the generated test identity."

log "waiting for the installed system to reach a healthy running state ..."
settled=0
system_state="starting"
for ((i = 0; i < 120; i++)); do
  kill -0 "$QEMU_PID" 2>/dev/null || die "installed VM exited while systemd was settling (see $SERIAL)"
  system_state="$(ssh_vm systemctl is-system-running 2>/dev/null || true)"
  case "$system_state" in
    running) settled=1; break ;;
    degraded|maintenance|emergency) break ;;
  esac
  sleep 5
done

if [ "$settled" != 1 ]; then
  warn "installed system did not reach running state (state=$system_state)"
  ssh_vm systemctl --failed --no-pager --no-legend 2>&1 || true
  ssh_vm systemctl status home-manager-feltfomo.service --no-pager -l 2>&1 || true
  ssh_vm journalctl -b -u home-manager-feltfomo.service --no-pager -n 200 2>&1 || true
  die "installed system health proof failed (state=$system_state); see $SERIAL"
fi

ssh_vm systemctl is-active --quiet furnish.service \
  || die "installed system is running but furnish.service is not active"
ssh_vm getent passwd feltfomo >/dev/null \
  || die "installed system is running but the primary test user is missing"

log "installed $HOST is running, furnish is active, and the primary user exists. PASS."
log "done."