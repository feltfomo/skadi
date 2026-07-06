#!/usr/bin/env bash
# skadi-install [<host>] [--drop a,b,c] [--print-target]  -- two-phase reinstall,
#   run from the skadi installer ISO.  --drop removes named TOP-LEVEL aspects
#   from the host for this install only (via the mkInstallTarget factory); the
#   committed nixosConfigurations.<host> and modules/hosts/<host>.nix are never
#   touched.
#   1. disko format+mount   2. host key + sops secrets into /persist
#   3. nixos-install
#
#   With NO <host> on a TTY it drops into an interactive picker (host, then
#   which top-level aspects to drop) that dispatches into the exact same path as
#   an explicit `<host> --drop ...`.  --print-target is a read-only dry run:
#   print the resolved invocation + the composed system's toplevel drvPath and
#   exit, with no disk writes (so it runs on a booted host too -- handy for
#   proving an interactive pick resolves to the same drvPath as `--drop`).
#
# Home repos (Wallpapers + notion-sync mappings) are cloned on first boot by the
# bootstrap-repos aspect, not here -- so this stays a pure OS bootstrapper.
#
# NEVER run against a booted skadi system -- disko repartitions. Guarded below.
# set -euo pipefail is injected by writeShellApplication.

SKADI_REMOTE="https://github.com/feltfomo/skadi"

MNT=/mnt
WORK=/tmp/skadi-install

log()  { printf '\033[0;32m[skadi-install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[skadi-install]\033[0m %s\n' "$*"; }
die()  { printf '\033[0;31m[skadi-install]\033[0m %s\n' "$*" >&2; exit 1; }

# Generic host disk detection ([C]/[G1]): the generic target ships NO committed
# _generic/{device,hardware}.nix for the machine in front of us -- discover them
# at install time. Enumerate whole disks (lsblk type=disk excludes the ISO's
# sr0/rom + loop devices), require EXACTLY one, set GENERIC_DEVICE. Multi-disk
# metal deliberately dies pointing at the deferred interactive-generic follow-on
# rather than guessing which disk to destroy.
detect_generic_disk() {
  local disks_json disks=() n
  disks_json="$(lsblk --json --nodeps --output NAME,TYPE)" || die "generic: lsblk failed enumerating disks"
  mapfile -t disks < <(jq -r '.blockdevices[] | select(.type=="disk") | .name' <<<"$disks_json")
  n="${#disks[@]}"
  if [ "$n" -eq 0 ]; then
    die "generic: no whole-disk device detected (lsblk saw none). This slice installs to a single internal disk -- attach one and retry."
  elif [ "$n" -gt 1 ]; then
    lsblk --nodeps --output NAME,SIZE,TYPE,MODEL >&2
    die "generic: found $n disks but this slice auto-installs to EXACTLY one. Interactive multi-disk selection for 'generic' is a planned 2e follow-on and isn't wired yet -- for multi-disk hardware add an explicit per-host layout (khion/lumi-style modules/hosts/_<host>/{disko,hardware}.nix)."
  fi
  GENERIC_DEVICE="/dev/${disks[0]}"
  log "generic: detected sole target disk $GENERIC_DEVICE"
}

# interactive target selection (no host arg, on a TTY): pick a host, toggle
# which of its TOP-LEVEL aspects to drop, confirm, then set HOST + DROP and let
# the normal path take over. Everything is enumerated from real config via
# narrow `nix eval` -- never a hardcoded menu. The aspect list is
# flake.lib.<system>.hostAspects, the SAME list mkInstallTarget validates --drop
# against (modules/install-target.nix), so an interactive pick can never produce
# an invalid drop: the fail-loud assertion only ever needs to guard the explicit
# --drop path. `base` is structurally required and is never offered as a toggle.
select_target() {
  local all=() hosts=() aspects=() drop_flag=() hosts_json aspects_json h i n choice csv

  # host list = nixosConfigurations that also have a modules/hosts/<h>.nix -- the
  # same filter the explicit path validates against, so the ISO's own `installer`
  # config (modules/installer.nix, no hosts/ file) never shows up as a target.
  hosts_json="$(nix eval --json "${WORK}#nixosConfigurations" --apply 'builtins.attrNames')" \
    || die "could not enumerate hosts (nix eval failed)"
  mapfile -t all < <(jq -r '.[]' <<<"$hosts_json")
  for h in "${all[@]}"; do
    # generic is an explicit-trigger-only target (`skadi-install generic`): it has
    # a modules/hosts/generic.nix so it'd pass this filter, but its disk + hardware
    # are DISCOVERED at install time, so it must never appear as a menu pick ([G2]).
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

  # top-level aspects for the chosen host, from the shared introspection output
  # (the SAME list --drop is validated against, so this menu can't misfire).
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

  # confirmation summary + the equivalent explicit invocation (teaches the CLI
  # and doubles as a sanity check that interactive resolves to the same target
  # as `--drop`).
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

# skadi-install <host> [--drop a,b,c]: <host> is positional; --drop takes a
# comma/space-separated list of TOP-LEVEL aspects to remove from this host for
# this install only (see modules/install-target.nix).
HOST=""
DROP=()
PRINT_TARGET=0
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
    -*) die "unknown flag: $1 (usage: skadi-install [<host>] [--drop a,b,c] [--print-target])" ;;
    *)  [ -z "$HOST" ] || die "unexpected extra argument: $1"; HOST="$1"; shift ;;
  esac
done
# NOTE: no mandatory-host check here. A missing host is resolved AFTER the clone:
# interactively on a TTY, otherwise a usage die. (DROP_NIX/DROP_CSV are rendered
# there too, once interactive selection has had its say.)

# guard: refuse to run on a booted skadi install (disko would repartition it).
# --print-target is a read-only dry run (no disk writes at all), so it bypasses
# this guard on purpose -- that's what lets it resolve a drvPath on khion itself.
if [ "$PRINT_TARGET" != 1 ] && [ ! -d /iso ] && [ -e /persist/etc/skadi ]; then
  die "this looks like a booted skadi system, not the ISO -- refusing to repartition."
fi

# clone the flake we install from (writable tree with .git for notion-sync).
rm -rf "$WORK"
log "cloning skadi from $SKADI_REMOTE"
git clone "$SKADI_REMOTE" "$WORK"
cd "$WORK"

# the builder's system, used to address flake.lib.<system>.* -- the interactive
# menu's hostAspects introspection, --print-target, and the mkInstallTarget
# factory all live there. Computed unconditionally now that the menu needs it.
SYSTEM="$(nix eval --raw --impure --expr builtins.currentSystem)"

# Resolve the host. With a host arg, use it as-is. With NO host arg, drop into
# interactive selection -- but ONLY on a real TTY and only when NOT unattended,
# so the harness / any piped or unattended caller stays fully non-interactive.
# The two non-interactive corners -- SKADI_INSTALL_UNATTENDED=1 + no host, and a
# piped / non-TTY caller + no host -- both fall through to the usage die rather
# than hang waiting on stdin.
if [ -z "$HOST" ]; then
  if [ "${SKADI_INSTALL_UNATTENDED:-}" != 1 ] && [ -t 0 ]; then
    select_target
  else
    die "usage: skadi-install <host> [--drop a,b,c] [--print-target]   (e.g. skadi-install khion --drop gpu-nvidia)"
  fi
fi

# `base` is structurally required -- it carries skadi.installer + provision and
# every host needs it to boot. Dropping it PASSES the top-level-name assertion in
# mkInstallTarget (base is a real top-level include) but yields a broken host, so
# reject it explicitly. The interactive menu never offers base, so this only ever
# fires on an explicit `--drop base`.
for a in "${DROP[@]}"; do
  if [ "$a" = base ]; then
    die "'base' is required and cannot be dropped"
  fi
done

# Render the drop list once: a nix list fragment ("a" "b" ) and a human CSV.
DROP_NIX=""
DROP_CSV=""
for a in "${DROP[@]}"; do DROP_NIX+="\"$a\" "; DROP_CSV+="${DROP_CSV:+,}$a"; done

# cheap pre-check, then the authoritative den-aware check: the host must actually
# resolve to a nixosConfigurations.<host>, not merely have a file by that name.
# (An interactive host already came from this exact list, so this just re-affirms
# it; an explicit `<host>` arg is validated here for the first time.)
test -f "modules/hosts/${HOST}.nix" || die "unknown host '$HOST' (no modules/hosts/${HOST}.nix)"
nix eval --json "${WORK}#nixosConfigurations" --apply 'builtins.attrNames' \
  | jq -e --arg h "$HOST" 'index($h)' >/dev/null \
  || die "unknown host '$HOST' (not in nixosConfigurations)"

# Generic host ([C]/[G1]): no committed _generic/{device,hardware}.nix describes
# THIS machine, so discover them. Detect the disk, write _generic/device, and
# write the vm-test sentinel from EXACTLY the IN_DISKO_TEST signal disko's key
# enroll uses (so the format-time key and the boot-time keyFile can never
# disagree), then git-add so the git+file flake eval + `disko --flake` see them.
# hardware.nix is generated later, once disko has mounted /mnt. Skipped under
# --print-target (that stays a read-only eval of the committed sentinel).
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

# Select the install target: the canonical host, or -- with --drop -- that host
#     composed with named top-level aspects removed, via the mkInstallTarget
#     factory (modules/install-target.nix). eval_target and build_target below
#     BOTH point at the same target, so a dropped aspect's tunables, secrets, and
#     closure all disappear together: we never prompt for a secret whose aspect
#     was dropped. The canonical branch is the exact old attr path; the --drop
#     branch is an --impure --expr over the same git-aware $WORK clone (so
#     Hyprland's gitTracked still holds), mirroring the proven spike invocation.
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

# --print-target: read-only dry run. Print the resolved invocation + the composed
#     system's toplevel drvPath, then exit BEFORE any disk work (it already
#     bypassed the booted-skadi guard above, so this also runs on khion itself).
#     This is the machine-checkable proof that interactive selection resolves to
#     the IDENTICAL target as an explicit `--drop`: pick the same host + aspects
#     both ways, and the drvPaths are equal. Evaluating .drvPath does NOT build.
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

# read this host's installer tunables as data (one narrow eval, never the
#     whole config, so it can't touch a package src / trip gitTracked). every
#     value defaults in modules/aspects/installer-tunables.nix to the literal it
#     replaces, so behavior is identical to the old hardcoded script. On --drop
#     this evals the COMPOSED target and is the FIRST thing to force the factory,
#     so a bad --drop name fails loud HERE -- before disko touches the disk.
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
disko --mode destroy,format,mount --flake ".#${HOST}"

# Generic host ([C]/[G1]): the target is now partitioned + mounted at /mnt, so
# generate its hardware profile from THIS machine and stage it over the committed
# placeholder BEFORE the closure build reads it. disko owns the filesystems, so
# --no-filesystems; the generated file stays pure (no fileSystems, no ttyS0 /
# keyfile -- those live in the IN_DISKO_TEST-gated vm-test-hooks.nix).
if [ "$HOST" = generic ]; then
  log "generic: generating hardware.nix from detected hardware"
  nixos-generate-config --no-filesystems --root "$MNT" --show-hardware-config > modules/hosts/_generic/hardware.nix || die "generic: nixos-generate-config failed"
  git add -A modules/hosts/_generic/hardware.nix
fi

# temporary build swap: guaranteed headroom so a from-source compile can never
#     OOM-kill the install on a lean-RAM box. Lix (deliberately uncached -- the
#     disk canary) and the first-party notion-sync daemon always build from source
#     here; on 8-16 GB that needs swap to survive. Placed on the target
#     btrfs (no-COW via mkswapfile) and torn down on exit (impermanence would drop
#     it on first boot anyway, but we clean it up regardless).
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

# relocate the Nix store's writable layer onto the target DISK.
#     The installer ISO mounts /nix/store as an overlay whose upper/work live on
#     a RAM-backed tmpfs (/nix/.rw-store; see nixpkgs iso-image.nix). That RAM
#     ceiling -- NOT the disk -- is what OOMs a cold from-source build. We stack
#     a SECOND overlay over /nix/store with upper/work on /mnt, layered ONLY over
#     the squashfs base (/nix/.ro-store).
#
#     CRITICAL -- lowerdir is the squashfs ALONE; we deliberately do NOT include
#     the ISO's tmpfs rw layer (/nix/.rw-store/store) as a lower. Stacking that
#     tmpfs layer poisons root chown on the merged store: even full-cap real root
#     then gets EPERM chown'ing store files, which breaks `tar --same-owner`
#     during rust vendoring (codemap: "tar: .gitignore: Cannot change ownership
#     to uid 1000 ... Operation not permitted"). Proven on the live installer: an
#     overlay with lowerdir=/nix/.ro-store + a btrfs upper accepts `chown 1000`,
#     while the tmpfs-lower'd store rejects it. The squashfs holds the ISO's base
#     closure; the only thing in the tmpfs layer is post-boot writes (notably the
#     flake source disko copies in), which we migrate into our disk upper below
#     before mounting so the RAM-resident Nix DB stays consistent.
#
#     This keeps the store path literally "/nix/store", i.e. NON-DIVERTED
#     (realStoreDir == storeDir), so build + eval share one store (no unsigned
#     cross-store copy, gitTracked stays git-aware). NOTE: non-diverted is NOT
#     what fixes the logseq `EACCES ... unlink esbuild_*.tgz` -- that turned out
#     to be a build-user privilege artifact of the old root local-store build;
#     building like khion (daemon + nixbld + sandbox) avoids it, no
#     root build needed. This overlay's only job is to move
#     the writable store off the RAM tmpfs onto disk so a cold from-source build
#     can't OOM the ISO's RAM ceiling (verified: hello built from source, output
#     landing on /mnt, not RAM).
STORE_RW="$MNT/nix-build-rw"
mkdir -p "$STORE_RW/store" "$STORE_RW/work"
# canonical /nix/store perms so the daemon's nixbld builders can write the merged
# store: overlayfs takes the upperdir's mode for the merged dir, so setting it on
# the disk upper is what the daemon and its build users see after the mount.
chown root:nixbld "$STORE_RW/store"
chmod 1775 "$STORE_RW/store"
# Carry over anything already written to the store's current writable (tmpfs)
# layer since boot -- CRUCIALLY the flake source that `disko --flake` (section 1)
# just copied in and REGISTERED in the RAM-resident Nix DB. We are about to drop
# that tmpfs layer from the overlay's lowerdir (it poisons root chown), so its
# contents must be migrated into our disk-backed upper FIRST. Otherwise those
# paths vanish from /nix/store while the DB still lists them as valid, so the
# the later `nix build` skips re-copying the flake source and dies with
# "getting status of '/nix/store/<hash>-source/flake.nix': No such file or
# directory". Store writes are pure additions (no overlay whiteouts), so a plain
# cp -a of the delta into our upper is safe.
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

# daemon build scratch on the target disk. build-dir=/mnt/nix-build-tmp is
#     baked into installer.nix; the daemon createDirs() it on first build, but
#     make it here too so it's unambiguous. NOTE: the client TMPDIR does NOT
#     reach the daemon builder (startBuilder unpacks into settings.build-dir), so
#     the old `export TMPDIR` was a no-op for the from-source builds once the
#     build stopped using --store local -- the setting is what moves scratch off
#     the ISO tmpfs (logseq node_modules, Lix cargo target, spicetify npm-deps).
mkdir -p "$MNT/nix-build-tmp"
log "daemon build scratch -> $MNT/nix-build-tmp (on target disk, not tmpfs)"

# host keys -> /persist, derive age recipient, rewrite .sops.yaml.
install -d -m0755 "$MNT/persist/etc/ssh"
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

# provision secrets: derive the set + how to fill each one from the host
#    config, then write + encrypt secrets/secrets.yaml. replaces the old
#    hand-written per-user block -- adding a user or a secret-bearing aspect
#    teaches this loop automatically, no edit here. eval a NARROW attr
#    (skadi.provision.secrets), never the whole config, so it never touches a
#    package src and can't trip Hyprland's gitTracked.
provision_secrets() {
  local plan name method prompt format optional placeholder value raw envvar
  plan="$(eval_target .config.skadi.provision.secrets)"
  install -d -m0755 secrets
  : > secrets/secrets.yaml
  for name in $(jq -r 'keys[]' <<<"$plan"); do
    method=$(jq -r --arg n "$name" '.[$n].method'           <<<"$plan")
    prompt=$(jq -r --arg n "$name" '.[$n].prompt'           <<<"$plan")
    format=$(jq -r --arg n "$name" '.[$n].format'           <<<"$plan")
    optional=$(jq -r --arg n "$name" '.[$n].optional'       <<<"$plan")
    placeholder=$(jq -r --arg n "$name" '.[$n].placeholder' <<<"$plan")
    # unattended (SKADI_INSTALL_UNATTENDED=1): each secret <name> is supplied via
    # env SKADI_SECRET_<NAME> (name uppercased, '-' -> '_'). mkpasswd expects the
    # final sha-512 hash; paste expects the raw token (its format is still applied).
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

provision_secrets

# copy flake to /persist/etc/skadi (impermanence-persisted) and install.
install -d -m0755 "$MNT/persist/etc"
rm -rf "$MNT/persist/etc/skadi"
cp -a "$WORK" "$MNT/persist/etc/skadi"
# Build the system closure with `nix build` FIRST, then install the prebuilt
# closure with `nixos-install --system`. We must NOT use `nixos-install --flake`
# here: it copies the flake + its inputs into the TARGET store (/mnt) and
# re-evaluates there, so upstream Hyprland's `src = fs.gitTracked ../.` runs
# against a .git-less /mnt copy and hard-fails ("not a local working tree of a
# Git repository"). `nix build` evaluates against the installer's own store
# (inputs still git-aware) and substitutes the desktop from the trusted caches,
# so there is no gitTracked and no from-source Hyprland build.
#
# The build runs through the nix-daemon in the DEFAULT (non-diverted) store,
# which the store relocation above moved onto the target disk. Two things matter here:
#   * NON-DIVERTED (note: NO `--store local`, NO `--store "local?root=/mnt"`):
#     realStoreDir == storeDir, so build + eval share one store -- gitTracked
#     stays git-aware and there's no unsigned cross-store copy. It also means
#     Lix does NOT auto-enable the sandbox for a diverted store; ours is on
#     because installer.nix asks for it.
#   * DISK-BACKED (via the overlay above): OUTPUTS land on /mnt, not the ISO's RAM
#     tmpfs, so a cold from-source build survives lean 8-16 GB machines. Build
#     SCRATCH is handled separately by build-dir=/mnt/nix-build-tmp in
#     installer.nix -- the daemon unpacks there, NOT under the client TMPDIR.
# Substituters + trusted keys now live in installer.nix (base + the desktop
# upstreams: Hyprland/walker/noctalia), so the daemon substitutes those with no
# inline --substituters here. Lix is deliberately NOT among them: its cargo
# target is the disk-pressure canary, so it builds from source every install --
# that's the point. notion-sync and the rest of the fleet closure build from
# source too; only third-party upstreams are fetched.
# basic disk resilience. NO Lix
#     cache on purpose -- Lix builds from source (its cargo target is the biggest
#     disk hog and the ENOSPC canary), alongside notion-sync + the fleet closure,
#     so the cold-build stress path stays fully exercised. Only base + the desktop
#     upstreams are substituted.
#   * preflight: fail fast BEFORE the long build if the disk clearly can't hold it.
#   * min/max-free: nix GCs unneeded store paths mid-build when space gets tight.
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
# --max-jobs 1: serialize derivations so only ONE big source build holds scratch
#   at a time (the multi-build pile-up + Lix's doubled debuginfo target ENOSPC'd
#   the 100 GB VM). --cores 0 keeps each package on all cores (per-build speed
#   unchanged); we only drop cross-package parallelism -- leaner, slower.
# --min-free/--max-free: nix GCs unneeded store paths mid-build when disk is tight.
# Everything that used to live here -- --store local, build-users-group "",
#   sandbox false, inline --substituters/--trusted-public-keys -- is GONE. The
#   build now goes through the daemon with stock nixbld users and the sandbox ON,
#   exactly like khion: that's what gives FODs a real userns (pasta works, no
#   "sandbox network setup timed out") and keeps builds pure (no /homeless-shelter
#   carryover between derivations). Caches + build-dir + sandbox are baked into
#   installer.nix; the store relocation above gives the daemon a writable on-disk store. The old
#   logseq `EACCES ... unlink esbuild_*.tgz` was a build-user privilege artifact
#   of the root local-store build -- khion builds the identical drv fine as
#   nixbld, so building its way avoids it with no root build needed.
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
