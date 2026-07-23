#!/usr/bin/env bash
# skadi-install [<host>] [--drop a,b,c] [--print-target] [--yes-wipe-all-disks]: two-phase reinstall from
# the installer iso. steps: disko format+mount, host key + sops secrets into
# /persist, nixos-install. --drop removes named top-level aspects for this install
# only via mkInstallTarget; the committed nixosConfigurations.<host> and
# modules/hosts/<host>.nix are never touched. no host on a tty opens an
# interactive picker that resolves to the same path as an explicit --drop.
# --print-target is a read-only dry run: prints the resolved invocation and the
# composed toplevel drvPath, no disk writes.
#
# home repos clone on first boot via bootstrap-repos, not here.
# never run against a booted skadi system -- disko repartitions. guarded below.
# set -euo pipefail is injected by writeShellApplication.

SKADI_REMOTE="https://github.com/feltfomo/skadi"

MNT=/mnt
WORK=/tmp/skadi-install

log()  { printf '\033[0;32m[skadi-install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[skadi-install]\033[0m %s\n' "$*"; }
die()  { printf '\033[0;31m[skadi-install]\033[0m %s\n' "$*" >&2; exit 1; }

# generic ships no committed _generic/{device,hardware}.nix for the machine in
# front of us, so discover the disk at install time. enumerate whole disks
# (lsblk type=disk excludes the iso's sr0/rom + loop devices), require exactly
# one, set GENERIC_DEVICE. multi-disk metal dies rather than guess which disk to
# destroy.
detect_generic_disk() {
  local disks_json disks=() n
  disks_json="$(lsblk --json --nodeps --output NAME,TYPE)" || die "generic: lsblk failed enumerating disks"
  mapfile -t disks < <(jq -r '.blockdevices[] | select(.type=="disk") | .name' <<<"$disks_json")
  n="${#disks[@]}"
  if [ "$n" -eq 0 ]; then
    die "generic: no whole-disk device detected (lsblk saw none). This slice installs to a single internal disk -- attach one and retry."
  elif [ "$n" -gt 1 ]; then
    lsblk --nodeps --output NAME,SIZE,TYPE,MODEL >&2
    die "generic: found $n disks but this slice auto-installs to EXACTLY one. Interactive multi-disk selection isn't wired yet; add an explicit per-host layout for multi-disk hardware (khion/lumi-style modules/hosts/_<host>/{disko,hardware}.nix)."
  fi
  GENERIC_DEVICE="/dev/${disks[0]}"
  log "generic: detected sole target disk $GENERIC_DEVICE"
}

# interactive target selection when no host arg on a tty: pick a host, toggle
# which top-level aspects to drop, then set HOST + DROP and hand off to the normal
# path. the menu is enumerated from flake.lib.<system>.hostAspects, the same list
# mkInstallTarget validates --drop against, so an interactive pick can't produce
# an invalid drop. base is required and never offered as a toggle.
select_target() {
  local all=() hosts=() aspects=() drop_flag=() hosts_json aspects_json h i n choice csv

  # hosts = nixosConfigurations that also have a modules/hosts/<h>.nix, so the
  # iso's own installer config (no hosts/ file) never shows up as a target.
  hosts_json="$(nix eval --json "${WORK}#nixosConfigurations" --apply 'builtins.attrNames')" \
    || die "could not enumerate hosts (nix eval failed)"
  mapfile -t all < <(jq -r '.[]' <<<"$hosts_json")
  for h in "${all[@]}"; do
    # generic is explicit-trigger-only: it passes this filter but its disk and
    # hardware are discovered at install time, so never offer it in the menu.
    if [ "$h" = generic ]; then continue; fi
    if [ -f "modules/hosts/${h}.nix" ]; then hosts+=("$h"); fi
  done
  [ "${#hosts[@]}" -gt 0 ] || die "no installable hosts (nixosConfigurations with a modules/hosts/<host>.nix)"

  echo "Select a host to install:" >&2
  for i in "${!hosts[@]}"; do printf '  %d) %s\n' "$((i + 1))" "${hosts[i]}" >&2; done
  while :; do
    read -r -p "host [1-${#hosts[@]}]: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#hosts[@]}" ]; then
      HOST="${hosts[$((choice - 1))]}"; break
    fi
    echo "  enter a number between 1 and ${#hosts[@]}" >&2
  done

  # top-level aspects for the chosen host, the same list --drop is validated against.
  aspects_json="$(nix eval --json "${WORK}#lib.${SYSTEM}.hostAspects.${HOST}")" \
    || die "could not read top-level aspects for '$HOST' (nix eval failed)"
  mapfile -t aspects < <(jq -r '.[]' <<<"$aspects_json")
  for _ in "${aspects[@]}"; do drop_flag+=(0); done

  echo >&2
  echo "Top-level aspects for '$HOST' -- number toggles drop, blank continues:" >&2
  while :; do
    for i in "${!aspects[@]}"; do
      n="${aspects[i]}"
      if [ "$n" = base ]; then
        printf '  %2d) [keep] %s (required)\n' "$((i + 1))" "$n" >&2
      elif [ "${drop_flag[i]}" = 1 ]; then
        printf '  %2d) [DROP] %s\n' "$((i + 1))" "$n" >&2
      else
        printf '  %2d) [keep] %s\n' "$((i + 1))" "$n" >&2
      fi
    done
    read -r -p "toggle # (blank = done): " choice
    [ -z "$choice" ] && break
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#aspects[@]}" ]; then
      echo "  enter a number between 1 and ${#aspects[@]}, or blank to continue" >&2
      continue
    fi
    i=$((choice - 1))
    if [ "${aspects[i]}" = base ]; then
      echo "  base is required and cannot be dropped" >&2
      continue
    fi
    if [ "${drop_flag[i]}" = 1 ]; then drop_flag[i]=0; else drop_flag[i]=1; fi
  done

  DROP=()
  for i in "${!aspects[@]}"; do
    if [ "${drop_flag[i]}" = 1 ]; then DROP+=("${aspects[i]}"); fi
  done

  # confirmation summary + the equivalent explicit invocation.
  csv=""
  for n in "${DROP[@]}"; do csv+="${csv:+,}$n"; done
  echo >&2
  echo "About to install:" >&2
  echo "  host: $HOST" >&2
  echo "  drop: ${csv:-(none)}" >&2
  if [ -n "$csv" ]; then
    echo "  equivalent to: skadi-install $HOST --drop $csv" >&2
  else
    echo "  equivalent to: skadi-install $HOST" >&2
  fi
  read -r -p "proceed? [y/N]: " choice
  case "$choice" in
    y | Y | yes | YES) ;;
    *) die "aborted" ;;
  esac
}

# <host> is positional; --drop takes a comma/space-separated list of top-level
# aspects to remove from this host for this install only.
HOST=""
DROP=()
PRINT_TARGET=0
YES_WIPE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --drop)
      [ -n "${2:-}" ] || die "--drop needs a comma-separated aspect list (e.g. --drop gpu-nvidia)"
      IFS=', ' read -r -a _drop_raw <<<"$2"; shift 2
      for a in "${_drop_raw[@]}"; do [ -n "$a" ] || continue; DROP+=("$a"); done ;;
    --drop=*)
      IFS=', ' read -r -a _drop_raw <<<"${1#--drop=}"; shift
      for a in "${_drop_raw[@]}"; do [ -n "$a" ] || continue; DROP+=("$a"); done ;;
    --print-target) PRINT_TARGET=1; shift ;;
    --yes-wipe-all-disks) YES_WIPE=1; shift ;;
    -*) die "unknown flag: $1 (usage: skadi-install [<host>] [--drop a,b,c] [--print-target] [--yes-wipe-all-disks])" ;;
    *)  [ -z "$HOST" ] || die "unexpected extra argument: $1"; HOST="$1"; shift ;;
  esac
done
# no host check here: a missing host is resolved after the clone, interactively on
# a tty or a usage die otherwise.

# refuse to run on a booted skadi install -- disko would repartition it.
# --print-target is read-only so it bypasses this guard on purpose, which is what
# lets it resolve a drvPath on khion itself.
if [ "$PRINT_TARGET" != 1 ] && [ ! -d /iso ] && [ -e /persist/etc/skadi ]; then
  die "this looks like a booted skadi system, not the ISO -- refusing to repartition."
fi

# obtain the flake we install from (writable tree with .git for notion-sync).
# SKADI_INSTALL_SOURCE lets a caller pin us to a pre-staged source tree instead of
# cloning from GitHub at run time -- the rebuild-vm-golden harness stages one
# deterministic pinned-rev worktree and points both its disko dry-run probe and
# this install at it, so probe and wipe validate byte-identical config. The tree
# must be a real git worktree (git+file eval, hyprland's gitTracked, notion-sync
# all require .git).
if [ -n "${SKADI_INSTALL_SOURCE:-}" ]; then
  [ -d "${SKADI_INSTALL_SOURCE}/.git" ] || die "SKADI_INSTALL_SOURCE=$SKADI_INSTALL_SOURCE is not a git worktree"
  WORK="$SKADI_INSTALL_SOURCE"
  log "using pre-staged pinned source at $WORK (skipping clone from $SKADI_REMOTE)"
else
  rm -rf "$WORK"
  log "cloning skadi from $SKADI_REMOTE"
  git clone "$SKADI_REMOTE" "$WORK"
fi
cd "$WORK"

# the builder's system, used to address flake.lib.<system>.* (the menu's
# hostAspects, --print-target, and mkInstallTarget all live there).
SYSTEM="$(nix eval --raw --impure --expr builtins.currentSystem)"

# resolve the host. with a host arg use it as-is. with no host arg, only drop into
# interactive selection on a real tty and when not unattended, so a piped or
# unattended caller falls through to the usage die instead of hanging on stdin.
if [ -z "$HOST" ]; then
  if [ "${SKADI_INSTALL_UNATTENDED:-}" != 1 ] && [ -t 0 ]; then
    select_target
  else
    die "usage: skadi-install <host> [--drop a,b,c] [--print-target] [--yes-wipe-all-disks]   (e.g. skadi-install khion --drop gpu-nvidia)"
  fi
fi

# base is required -- it carries skadi.installer + provision and every host needs
# it to boot. dropping it passes the mkInstallTarget name check but yields a broken
# host, so reject it explicitly.
for a in "${DROP[@]}"; do
  if [ "$a" = base ]; then
    die "'base' is required and cannot be dropped"
  fi
done

# Render the drop list once: a nix list fragment ("a" "b" ) and a human CSV.
DROP_NIX=""
DROP_CSV=""
for a in "${DROP[@]}"; do DROP_NIX+="\"$a\" "; DROP_CSV+="${DROP_CSV:+,}$a"; done

# cheap pre-check then the authoritative check: the host must resolve to a
# nixosConfigurations.<host>, not merely have a file by that name.
test -f "modules/hosts/${HOST}.nix" || die "unknown host '$HOST' (no modules/hosts/${HOST}.nix)"
nix eval --json "${WORK}#nixosConfigurations" --apply 'builtins.attrNames' \
  | jq -e --arg h "$HOST" 'index($h)' >/dev/null \
  || die "unknown host '$HOST' (not in nixosConfigurations)"

# generic: no committed _generic/{device,hardware}.nix describes this machine, so
# discover it. detect the disk, write _generic/device, and write the vm-test
# sentinel from the same IN_DISKO_TEST signal disko's key enroll uses so the
# format-time key and boot-time keyFile can't disagree, then git-add so the
# git+file flake eval and disko --flake see them. hardware.nix comes later once
# disko has mounted /mnt. skipped under --print-target.
if [ "$HOST" = generic ] && [ "$PRINT_TARGET" != 1 ]; then
  detect_generic_disk
  printf '%s' "$GENERIC_DEVICE" > modules/hosts/_generic/device
  if [ "${IN_DISKO_TEST:-}" = 1 ]; then
    printf '1' > modules/hosts/_generic/vm-test
  else
    printf '0' > modules/hosts/_generic/vm-test
  fi
  git add -A modules/hosts/_generic/device modules/hosts/_generic/vm-test
fi

# select the install target: the canonical host, or with --drop that host minus
# named top-level aspects via mkInstallTarget. eval_target and build_target both
# point at the same target, so a dropped aspect's tunables, secrets and closure
# disappear together and we never prompt for a secret whose aspect was dropped.
# the --drop branch uses --impure --expr over the same git-aware $WORK clone so
# hyprland's gitTracked still holds.
if [ "${#DROP[@]}" -gt 0 ]; then
  # composing: the flake exposes the factory under lib.<system>.mkInstallTarget
  # (SYSTEM was resolved above; the menu and --print-target need it too).
  log "composing '$HOST' minus top-level aspect(s): $DROP_CSV"
  log "  (canonical nixosConfigurations.$HOST and modules/hosts/$HOST.nix stay untouched)"
fi

# nix eval --json of a <selector> (e.g. .config.skadi.installer) on the target.
eval_target() {
  if [ "${#DROP[@]}" -eq 0 ]; then
    nix eval --json "${WORK}#nixosConfigurations.${HOST}${1}"
  else
    nix eval --impure --json \
      --expr "let s = builtins.getFlake \"git+file://${WORK}\"; in (s.lib.${SYSTEM}.mkInstallTarget { host = \"${HOST}\"; drop = [ ${DROP_NIX}]; })${1}"
  fi
}

# nix build of the target's system.build.toplevel (same RAM/disk-lean flags).
build_target() {
  if [ "${#DROP[@]}" -eq 0 ]; then
    nix build --no-link --print-out-paths \
      --max-jobs "$MAX_JOBS" --cores "$CORES" \
      --min-free "$MIN_FREE" --max-free "$MAX_FREE" \
      "${WORK}#nixosConfigurations.${HOST}.config.system.build.toplevel"
  else
    nix build --no-link --print-out-paths --impure \
      --max-jobs "$MAX_JOBS" --cores "$CORES" \
      --min-free "$MIN_FREE" --max-free "$MAX_FREE" \
      --expr "let s = builtins.getFlake \"git+file://${WORK}\"; in (s.lib.${SYSTEM}.mkInstallTarget { host = \"${HOST}\"; drop = [ ${DROP_NIX}]; }).config.system.build.toplevel"
  fi
}

# --print-target: read-only dry run. print the resolved invocation and the composed
# toplevel drvPath, then exit before any disk work (it bypassed the booted-skadi
# guard above so it runs on khion too). evaluating .drvPath does not build.
if [ "$PRINT_TARGET" = 1 ]; then
  if [ "${#DROP[@]}" -gt 0 ]; then
    echo "resolved: skadi-install $HOST --drop $DROP_CSV"
  else
    echo "resolved: skadi-install $HOST"
  fi
  if ! drv="$(eval_target .config.system.build.toplevel.drvPath)"; then
    die "could not evaluate the composed target's drvPath (see nix error above)."
  fi
  # eval_target returns the drvPath as a JSON string; unwrap it for a clean line.
  echo "drvPath: $(jq -r . <<<"$drv")"
  exit 0
fi

# read this host's installer tunables as data via one narrow eval, never the whole
# config so it can't touch a package src or trip gitTracked. on --drop this is the
# first thing to force the factory, so a bad --drop name fails loud here before
# disko touches the disk.
log "reading installer tunables from ${HOST} config"
if ! TUNABLES="$(eval_target .config.skadi.installer)"; then
  if [ "${#DROP[@]}" -gt 0 ]; then
    die "could not compose '$HOST' minus [$DROP_CSV] -- see the den error above (each --drop name must match a top-level aspect on $HOST)."
  fi
  die "could not read installer config for '$HOST' (see nix error above)."
fi
SWAP_SIZE_GIB=$(jq -r '.swapSizeGiB'                <<<"$TUNABLES")
LOW_RAM_THRESHOLD_GIB=$(jq -r '.lowRamThresholdGiB' <<<"$TUNABLES")
MIN_FREE_GIB=$(jq -r '.minFreeGiB'                  <<<"$TUNABLES")
MAX_FREE_GIB=$(jq -r '.maxFreeGiB'                  <<<"$TUNABLES")
DISK_FLOOR_GIB=$(jq -r '.diskFloorGiB'              <<<"$TUNABLES")
DISK_WARN_GIB=$(jq -r '.diskWarnGiB'                <<<"$TUNABLES")
MAX_JOBS=$(jq -r '.maxJobs'                         <<<"$TUNABLES")
CORES=$(jq -r '.cores'                              <<<"$TUNABLES")

# disko: destroy + format + mount at /mnt.
#    (older disko: swap the mode for `--mode disko`.)
lsblk
warn "about to DESTROY and repartition the disk in modules/hosts/_${HOST}/disko.nix"
if [ "${SKADI_INSTALL_UNATTENDED:-}" = 1 ]; then
  # unattended: the harness has already committed to destroying this disk.
  log "unattended: auto-confirming disk destroy for '$HOST'"
  confirm="$HOST"
else
  read -r -p "type '$HOST' to confirm: " confirm
fi
[ "$confirm" = "$HOST" ] || die "aborted"
log "running disko (destroy,format,mount)"
disko_wipe=()
[ "$YES_WIPE" = 1 ] && disko_wipe=(--yes-wipe-all-disks)
disko "${disko_wipe[@]}" --mode destroy,format,mount --flake ".#${HOST}"

# generic: /mnt is now mounted, so generate hardware.nix from this machine and
# stage it over the placeholder before the closure build reads it. disko owns the
# filesystems so --no-filesystems; the generated file stays pure (no fileSystems,
# no ttyS0/keyfile -- those live in the IN_DISKO_TEST-gated vm-test-hooks.nix).
if [ "$HOST" = generic ]; then
  log "generic: generating hardware.nix from detected hardware"
  nixos-generate-config --no-filesystems --root "$MNT" --show-hardware-config > modules/hosts/_generic/hardware.nix || die "generic: nixos-generate-config failed"
  git add -A modules/hosts/_generic/hardware.nix
fi

# temporary build swap so a from-source compile can't oom-kill the install on a
# lean-ram box. lix and notion-sync always build from source here; on 8-16g that
# needs swap. placed on the target btrfs (no-cow via mkswapfile) and torn down on exit.
SWAPFILE="$MNT/swapfile"
STORE_RELOCATED=0
teardown() {
  swapon --show=NAME --noheadings 2>/dev/null | grep -qxF "$SWAPFILE" && swapoff "$SWAPFILE" || true
  rm -f "$SWAPFILE"
  # drop the disk-backed store overlay + its build cruft (best-effort; a reboot
  # / impermanence would also clear it, but don't leave it on the target).
  if [ "${STORE_RELOCATED:-0}" = 1 ]; then
    umount -l /nix/store 2>/dev/null || true
    rm -rf "$STORE_RW" 2>/dev/null || true
  fi
}
trap teardown EXIT
mem_gib=$(( $(awk '/MemTotal/{print $2}' /proc/meminfo) / 1024 / 1024 ))
if [ "$mem_gib" -lt "$LOW_RAM_THRESHOLD_GIB" ]; then
  log "low RAM (${mem_gib}G): adding temporary ${SWAP_SIZE_GIB}G build swap at $SWAPFILE"
  btrfs filesystem mkswapfile --size "${SWAP_SIZE_GIB}g" "$SWAPFILE" 2>/dev/null || {
    truncate -s 0 "$SWAPFILE"; chattr +C "$SWAPFILE" 2>/dev/null || true
    fallocate -l "${SWAP_SIZE_GIB}G" "$SWAPFILE"; chmod 600 "$SWAPFILE"; mkswap "$SWAPFILE"
  }
  swapon "$SWAPFILE"
else
  log "RAM ${mem_gib}G >= ${LOW_RAM_THRESHOLD_GIB}G: skipping build swap"
fi

# relocate the nix store's writable layer onto the target disk. the iso mounts
# /nix/store as an overlay whose upper/work live on a ram tmpfs (/nix/.rw-store),
# and that ram ceiling is what ooms a cold from-source build. stack a second
# overlay over /nix/store with upper/work on /mnt, layered only over the squashfs
# base (/nix/.ro-store).
#
# lowerdir MUST be the squashfs alone -- do not include the iso's tmpfs rw layer.
# stacking it poisons root chown on the merged store: even full-cap root gets
# EPERM chown'ing store files, which breaks `tar --same-owner` during rust
# vendoring. the only thing in the tmpfs layer is post-boot writes (the flake
# source disko copies in), which we migrate into the disk upper below before
# mounting so the ram-resident nix db stays consistent.
#
# keeps the path literally /nix/store, i.e. non-diverted, so build and eval share
# one store (no unsigned cross-store copy, gitTracked stays git-aware).
STORE_RW="$MNT/nix-build-rw"
mkdir -p "$STORE_RW/store" "$STORE_RW/work"
# canonical /nix/store perms so the daemon's nixbld builders can write the merged
# store: overlayfs takes the upperdir's mode for the merged dir, so setting it on
# the disk upper is what the daemon and its build users see after the mount.
chown root:nixbld "$STORE_RW/store"
chmod 1775 "$STORE_RW/store"
# carry over post-boot tmpfs writes, crucially the flake source disko registered
# in the ram-resident nix db. we're about to drop the tmpfs layer, so migrate its
# contents into the disk upper first -- otherwise those paths vanish from
# /nix/store while the db still lists them valid and the later nix build dies with
# "No such file or directory" on the flake source. store writes are pure additions
# so a plain cp -a of the delta is safe.
if [ -d /nix/.rw-store/store ]; then
  log "migrating post-boot store writes (disko flake source, etc.) -> $STORE_RW/store"
  cp -a /nix/.rw-store/store/. "$STORE_RW/store/" 2>/dev/null || true
fi
log "relocating /nix/store writable layer -> $STORE_RW (disk-backed, non-diverted)"
mount -t overlay skadi-build \
  -o "lowerdir=/nix/.ro-store,upperdir=$STORE_RW/store,workdir=$STORE_RW/work" \
  /nix/store
mountpoint -q /nix/store || die "failed to relocate /nix/store onto $STORE_RW"
STORE_RELOCATED=1

# restart the daemon so it adopts the relocated on-disk store cleanly (drops any
# cached fds from before the mount). It already has build-dir=/mnt/nix-build-tmp
# and sandbox=true from installer.nix, so from here the daemon's builds land
# their scratch and outputs on the target disk, sandboxed, as stock nixbld users.
systemctl restart nix-daemon

# daemon build scratch on the target disk. build-dir=/mnt/nix-build-tmp is baked
# into installer.nix; make the dir here too so it's unambiguous. the client TMPDIR
# doesn't reach the daemon builder (it unpacks into build-dir), so the setting is
# what moves scratch off the iso tmpfs.
mkdir -p "$MNT/nix-build-tmp"
log "daemon build scratch -> $MNT/nix-build-tmp (on target disk, not tmpfs)"

# Host keys -> /persist. The disposable vm test uses a committed, explicitly
# unsafe test identity so its encrypted fixture and resulting closure are stable.
# Every other host keeps the ordinary fresh-key provisioning flow.
install -d -m0755 "$MNT/persist/etc/ssh"
VM_TEST_IDENTITY=0
VM_TEST_DIR="$WORK/modules/hosts/_vm"
VM_TEST_KEY="$VM_TEST_DIR/ssh_host_ed25519_key"
VM_TEST_PUB="$VM_TEST_KEY.pub"
VM_TEST_FIXTURE="$VM_TEST_DIR/secrets.yaml"

if [ "${IN_DISKO_TEST:-}" = 1 ] && [ "$HOST" = vm ]; then
  VM_TEST_IDENTITY=1
  for required in "$VM_TEST_KEY" "$VM_TEST_PUB" "$VM_TEST_FIXTURE"; do
    [ -f "$required" ] || die "vm test identity fixture missing: $required"
  done
  log "installing fixed TEST-ONLY vm host identity"
  install -m0600 "$VM_TEST_KEY" "$MNT/persist/etc/ssh/ssh_host_ed25519_key"
  install -m0644 "$VM_TEST_PUB" "$MNT/persist/etc/ssh/ssh_host_ed25519_key.pub"
  ssh-keygen -t rsa -b 4096 -N "" -C "root@vm-test" \
    -f "$MNT/persist/etc/ssh/ssh_host_rsa_key"
  chmod 600 "$MNT"/persist/etc/ssh/*_key
  chmod 644 "$MNT"/persist/etc/ssh/*_key.pub
  AGE_RECIP="$(ssh-to-age -i "$VM_TEST_PUB")"
  [ -n "$AGE_RECIP" ] || die "vm test identity has no age recipient"
else
  log "generating host SSH keys into /persist/etc/ssh"
  ssh-keygen -t ed25519 -N "" -C "root@${HOST}" -f "$MNT/persist/etc/ssh/ssh_host_ed25519_key"
  ssh-keygen -t rsa -b 4096 -N "" -C "root@${HOST}" -f "$MNT/persist/etc/ssh/ssh_host_rsa_key"
  chmod 600 "$MNT"/persist/etc/ssh/*_key
  chmod 644 "$MNT"/persist/etc/ssh/*_key.pub

  log "deriving age recipient from the new host key"
  AGE_RECIP="$(ssh-to-age -i "$MNT/persist/etc/ssh/ssh_host_ed25519_key.pub")"
  [ -n "$AGE_RECIP" ] || die "ssh-to-age produced no recipient"
  log "age recipient: $AGE_RECIP"
  cat > .sops.yaml <<EOF
creation_rules:
  - path_regex: secrets/secrets.yaml\$
    age: $AGE_RECIP
EOF
fi

# provision secrets: derive the set and how to fill each one from the host config,
# then write + encrypt secrets/secrets.yaml. adding a user or a secret-bearing
# aspect teaches this loop automatically. eval a narrow attr, never the whole
# config, so it can't touch a package src or trip gitTracked.
provision_secrets() {
  local plan name method prompt format optional placeholder value raw envvar
  plan="$(eval_target .config.skadi.provision.secrets)"
  if [ "${IN_DISKO_TEST:-}" = 1 ]; then
    # The checked-in rules target real machines, so test secrets use the fresh
    # VM host recipient instead.
    (
      umask 077
      local test_tmp target_map configured_sops_file target plaintext encrypted existing_target existing_plaintext
      test_tmp="$(mktemp -d)"
      trap 'rm -rf "$test_tmp"' EXIT
      target_map="$test_tmp/targets"
      : > "$target_map"

      for name in $(jq -r 'keys[]' <<<"$plan"); do
        method=$(jq -r --arg n "$name" '.[$n].method'           <<<"$plan")
        prompt=$(jq -r --arg n "$name" '.[$n].prompt'           <<<"$plan")
        format=$(jq -r --arg n "$name" '.[$n].format'           <<<"$plan")
        optional=$(jq -r --arg n "$name" '.[$n].optional'       <<<"$plan")
        placeholder=$(jq -r --arg n "$name" '.[$n].placeholder' <<<"$plan")
        envvar="SKADI_SECRET_$(printf '%s' "$name" | tr 'a-z-' 'A-Z_')"
        case "$method" in
          mkpasswd)
            value="${!envvar:-}"
            [ -n "$value" ] || die "$name is required (set $envvar to a sha-512 hash)"
            ;;
          placeholder) value=$(jq -r --arg n "$name" '.[$n].value' <<<"$plan") ;;
          paste)
            raw="${!envvar:-}"
            if [ -n "$raw" ]; then
              # shellcheck disable=SC2059  # trusted config template such as NOTION_TOKEN=%s
              value=$(printf "$format" "$raw")
            elif [ "$optional" = true ]; then
              value="$placeholder"
            else
              die "$name is required"
            fi
            ;;
          *) die "unknown provision method '$method' for $name" ;;
        esac

        configured_sops_file="$(eval_target ".config.sops.secrets.\"${name}\".sopsFile" | jq -r .)"
        [ -n "$configured_sops_file" ] && [ "$configured_sops_file" != null ] \
          || die "$name has no effective sopsFile"
        target="secrets/$(basename "$configured_sops_file")"
        plaintext=""
        while IFS=$'\t' read -r existing_target existing_plaintext; do
          if [ "$existing_target" = "$target" ]; then
            plaintext="$existing_plaintext"
            break
          fi
        done < "$target_map"
        if [ -z "$plaintext" ]; then
          plaintext="$(mktemp "$test_tmp/plaintext.XXXXXX")"
          chmod 0600 "$plaintext"
          printf '%s\t%s\n' "$target" "$plaintext" >> "$target_map"
        fi
        printf '%s: "%s"\n' "$name" "$value" >> "$plaintext"
      done

      while IFS=$'\t' read -r target plaintext; do
        [ -n "$target" ] || continue
        encrypted="$(mktemp "$test_tmp/encrypted.XXXXXX")"
        (
          cd "$test_tmp"
          sops --encrypt --age "$AGE_RECIP" --input-type yaml --output-type yaml \
            "$plaintext" > "$encrypted"
        )
        install -D -m0644 "$encrypted" "$target"
        rm -f "$encrypted"
        git add -A "$target"
      done < "$target_map"
    )
    return
  fi
  install -d -m0755 secrets
  : > secrets/secrets.yaml
  for name in $(jq -r 'keys[]' <<<"$plan"); do
    method=$(jq -r --arg n "$name" '.[$n].method'           <<<"$plan")
    prompt=$(jq -r --arg n "$name" '.[$n].prompt'           <<<"$plan")
    format=$(jq -r --arg n "$name" '.[$n].format'           <<<"$plan")
    optional=$(jq -r --arg n "$name" '.[$n].optional'       <<<"$plan")
    placeholder=$(jq -r --arg n "$name" '.[$n].placeholder' <<<"$plan")
    # unattended: each secret is supplied via env SKADI_SECRET_<NAME> (uppercased,
    # '-' -> '_'). mkpasswd expects the final sha-512 hash; paste expects the raw token.
    envvar="SKADI_SECRET_$(printf '%s' "$name" | tr 'a-z-' 'A-Z_')"
    case "$method" in
      mkpasswd)
        if [ "${SKADI_INSTALL_UNATTENDED:-}" = 1 ]; then
          value="${!envvar:-}"
          [ -n "$value" ] || die "$name is required (set $envvar to a sha-512 hash)"
        else
          log "set the $name"; value=$(mkpasswd -m sha-512)
        fi
        ;;
      placeholder) value=$(jq -r --arg n "$name" '.[$n].value' <<<"$plan") ;;
      paste)
        if [ "${SKADI_INSTALL_UNATTENDED:-}" = 1 ]; then
          raw="${!envvar:-}"
        else
          read -r -p "paste $prompt: " raw
        fi
        if [ -n "$raw" ]; then
          # shellcheck disable=SC2059  # $format is a trusted template like NOTION_TOKEN=%s
          value=$(printf "$format" "$raw")
        elif [ "$optional" = true ]; then
          value="$placeholder"
        else
          die "$name is required"
        fi
        ;;
      *) die "unknown provision method '$method' for $name" ;;
    esac
    printf '%s: "%s"\n' "$name" "$value" >> secrets/secrets.yaml
  done
  log "encrypting secrets/secrets.yaml to $AGE_RECIP"
  sops --encrypt --in-place secrets/secrets.yaml
  git add -A .sops.yaml secrets/secrets.yaml
}

assert_vm_test_identity() {
  local expected_pub installed_pub actual_names fixture_hash configured_file configured_hash
  local age_key decrypted

  expected_pub="$(cut -d' ' -f1-2 "$VM_TEST_PUB")"
  installed_pub="$(ssh-keygen -y -f "$MNT/persist/etc/ssh/ssh_host_ed25519_key")"
  [ "$installed_pub" = "$expected_pub" ] \
    || die "installed vm test host identity does not match committed public key"

  # The public test identity must never be a recipient of real encrypted files
  # or real creation rules. The real files must also remain byte-untouched.
  if grep -Fq "$AGE_RECIP" .sops.yaml secrets/lumi.yaml secrets/secrets.yaml; then
    die "SECURITY INVARIANT: vm test recipient appears in real SOPS material"
  fi
  git diff --quiet -- .sops.yaml secrets/lumi.yaml secrets/secrets.yaml \
    || die "SECURITY INVARIANT: real SOPS material changed during vm test install"

  actual_names="$(eval_target .config.sops.secrets | jq -c 'keys | sort')"
  [ "$actual_names" = '["feltfomo-password","notion-token"]' ] \
    || die "vm test identity expected exactly feltfomo-password + notion-token; got $actual_names"

  fixture_hash="$(sha256sum "$VM_TEST_FIXTURE" | awk '{print $1}')"
  for name in feltfomo-password notion-token; do
    configured_file="$(eval_target ".config.sops.secrets.\"${name}\".sopsFile" | jq -r .)"
    [ -f "$configured_file" ] || die "$name effective sopsFile is missing"
    configured_hash="$(sha256sum "$configured_file" | awk '{print $1}')"
    [ "$configured_hash" = "$fixture_hash" ] \
      || die "$name does not resolve to the committed _vm fixture"
  done

  age_key="$(mktemp)"
  chmod 0600 "$age_key"
  ssh-to-age -private-key -i "$MNT/persist/etc/ssh/ssh_host_ed25519_key" > "$age_key"
  decrypted="$(SOPS_AGE_KEY_FILE="$age_key" sops --decrypt --output-type json "$VM_TEST_FIXTURE")"
  rm -f "$age_key"
  jq -e '
    (keys | sort) == ["feltfomo-password", "notion-token"]
    and .["feltfomo-password"] == "$6$skadivmtest$tp5BUeNDHy1miR21O7X2QXROL/yxzqnT9XeKJ4UKI.PpyYdkise0/iV58ErEoKs5SuKbvW/xy93Mzu3lQ2Fgf0"
    and .["notion-token"] == "NOTION_TOKEN=REPLACE_ME"
  ' >/dev/null <<<"$decrypted" || die "vm test fixture plaintext failed invariant check"
  log "vm test identity assertions passed (fixed key, exact secret set, fixture decrypt, real secrets untouched)"
}

if [ "$VM_TEST_IDENTITY" = 1 ]; then
  assert_vm_test_identity
  log "using committed byte-identical vm test fixture; skipping provision_secrets"
else
  provision_secrets
fi

# copy flake to /persist/etc/skadi (impermanence-persisted) and install.
install -d -m0755 "$MNT/persist/etc"
rm -rf "$MNT/persist/etc/skadi"
cp -a "$WORK" "$MNT/persist/etc/skadi"
# build the closure with `nix build` first, then install it with
# `nixos-install --system`. do NOT use `nixos-install --flake`: it copies the
# flake + inputs into the target store (/mnt) and re-evaluates there, so upstream
# hyprland's `src = fs.gitTracked ../.` runs against a .git-less /mnt copy and
# hard-fails ("not a local working tree of a Git repository"). nix build evaluates
# against the installer's own git-aware store and substitutes the desktop from the
# trusted caches, so that branch never runs.
#
# the build goes through the daemon in the default non-diverted store (moved onto
# the target disk by the relocation above): build and eval share one store so
# gitTracked stays git-aware, and outputs land on /mnt not the iso's ram tmpfs so a
# cold from-source build survives lean 8-16g machines. substituters live in
# installer.nix; lix is not among them and builds from source every install (the
# disk canary), as does the rest of the fleet closure.
# disk resilience:
#   * preflight: fail fast before the long build if the disk can't hold it.
#   * min/max-free: nix gcs unneeded store paths mid-build when space gets tight.
avail_gib=$(( $(df -B1 --output=avail "$MNT" | tail -1) / 1024 / 1024 / 1024 ))
if [ "$avail_gib" -lt "$DISK_FLOOR_GIB" ]; then
  die "only ${avail_gib}G free on $MNT -- too small for the system closure (${DISK_FLOOR_GIB}G floor)."
elif [ "$avail_gib" -lt "$DISK_WARN_GIB" ]; then
  warn "only ${avail_gib}G free on $MNT -- ok for a cached install, tight for a COLD from-source build."
fi
log "disk preflight: ${avail_gib}G free on $MNT"
MIN_FREE=$((MIN_FREE_GIB * 1024 * 1024 * 1024))    # below this, nix GCs mid-build
MAX_FREE=$((MAX_FREE_GIB * 1024 * 1024 * 1024))    # GC target ceiling

log "building system closure for $HOST onto the target disk (RAM-lean, cached)"
# --max-jobs 1: serialize derivations so only one big source build holds scratch at
#   a time (the pile-up + lix's doubled debuginfo target enospc'd the 100g vm).
#   --cores 0 keeps each package on all cores; we only drop cross-package parallelism.
# --min-free/--max-free: nix gcs unneeded store paths mid-build when disk is tight.
# the build goes through the daemon with stock nixbld users and sandbox on, like
# khion: that gives fods a real userns (pasta works) and keeps builds pure.
if ! SYS_PATH="$(build_target)"; then
  warn "system build FAILED -- disk / OOM post-mortem:"
  df -h "$MNT" / || true
  dmesg 2>/dev/null | tail -n 30 | grep -iE 'out of memory|oom-kill|no space' || true
  die "nix build failed for $HOST (see disk/OOM diagnostics above)."
fi
[ -n "$SYS_PATH" ] || die "nix build produced no system path"
log "installing prebuilt closure: $SYS_PATH"
nixos-install --system "$SYS_PATH" --no-root-passwd

log "OS install done. home repos clone themselves on first boot (bootstrap-repos)."
log "reboot into $HOST, confirm login on a fresh tty, then run"
log "'tailscale funnel --bg 8080' once for notion-sync webhooks."
