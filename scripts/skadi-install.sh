#!/usr/bin/env bash
# skadi-install <host>  -- two-phase reinstall, run from the skadi installer ISO.
#   1. disko format+mount   2. host key + sops secrets into /persist
#   3. nixos-install
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

HOST="${1:-}"
[ -n "$HOST" ] || die "usage: skadi-install <host>   (e.g. skadi-install khion)"

# guard: refuse to run on a booted skadi install (disko would repartition it).
if [ ! -d /iso ] && [ -e /persist/etc/skadi ]; then
  die "this looks like a booted skadi system, not the ISO -- refusing to repartition."
fi

# 0. clone the flake we install from (writable tree with .git for notion-sync).
rm -rf "$WORK"
log "cloning skadi from $SKADI_REMOTE"
git clone "$SKADI_REMOTE" "$WORK"
cd "$WORK"
# cheap pre-check, then the authoritative den-aware check: the host must actually
# resolve to a nixosConfigurations.<host>, not merely have a file by that name.
test -f "modules/hosts/${HOST}.nix" || die "unknown host '$HOST' (no modules/hosts/${HOST}.nix)"
nix eval --json "${WORK}#nixosConfigurations" --apply 'builtins.attrNames' \
  | jq -e --arg h "$HOST" 'index($h)' >/dev/null \
  || die "unknown host '$HOST' (not in nixosConfigurations)"

# 0b. read this host's installer tunables as data (one narrow eval -- never the
#     whole config, so it can't touch a package src / trip gitTracked). every
#     value defaults in modules/aspects/installer-tunables.nix to the literal it
#     replaces, so behavior is identical to the old hardcoded script.
log "reading installer tunables from ${HOST} config"
TUNABLES="$(nix eval --json "${WORK}#nixosConfigurations.${HOST}.config.skadi.installer")"
SWAP_SIZE_GIB=$(jq -r '.swapSizeGiB'                <<<"$TUNABLES")
LOW_RAM_THRESHOLD_GIB=$(jq -r '.lowRamThresholdGiB' <<<"$TUNABLES")
MIN_FREE_GIB=$(jq -r '.minFreeGiB'                  <<<"$TUNABLES")
MAX_FREE_GIB=$(jq -r '.maxFreeGiB'                  <<<"$TUNABLES")
DISK_FLOOR_GIB=$(jq -r '.diskFloorGiB'              <<<"$TUNABLES")
DISK_WARN_GIB=$(jq -r '.diskWarnGiB'                <<<"$TUNABLES")
MAX_JOBS=$(jq -r '.maxJobs'                         <<<"$TUNABLES")
CORES=$(jq -r '.cores'                              <<<"$TUNABLES")

# 1. disko: destroy + format + mount at /mnt.
#    (older disko: swap the mode for `--mode disko`.)
lsblk
warn "about to DESTROY and repartition the disk in modules/hosts/_${HOST}/disko.nix"
read -r -p "type '$HOST' to confirm: " confirm
[ "$confirm" = "$HOST" ] || die "aborted"
log "running disko (destroy,format,mount)"
disko --mode destroy,format,mount --flake ".#${HOST}"

# 1b. temporary build swap: guaranteed headroom so a from-source compile can never
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

# 1c. relocate the Nix store's writable layer onto the target DISK.
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
#     building like khion (daemon + nixbld + sandbox, section 4) avoids it, no
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
# section-4 `nix build` skips re-copying the flake source and dies with
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

# 1d. daemon build scratch on the target disk. build-dir=/mnt/nix-build-tmp is
#     baked into installer.nix; the daemon createDirs() it on first build, but
#     make it here too so it's unambiguous. NOTE: the client TMPDIR does NOT
#     reach the daemon builder (startBuilder unpacks into settings.build-dir), so
#     the old `export TMPDIR` was a no-op for the from-source builds once the
#     build stopped using --store local -- the setting is what moves scratch off
#     the ISO tmpfs (logseq node_modules, Lix cargo target, spicetify npm-deps).
mkdir -p "$MNT/nix-build-tmp"
log "daemon build scratch -> $MNT/nix-build-tmp (on target disk, not tmpfs)"

# 2. host keys -> /persist, derive age recipient, rewrite .sops.yaml.
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

# 3. provision secrets: derive the set + how to fill each one from the host
#    config, then write + encrypt secrets/secrets.yaml. replaces the old
#    hand-written per-user block -- adding a user or a secret-bearing aspect
#    teaches this loop automatically, no edit here. eval a NARROW attr
#    (skadi.provision.secrets), never the whole config, so it never touches a
#    package src and can't trip Hyprland's gitTracked.
provision_secrets() {
  local host="$1" plan name method prompt format optional placeholder value raw
  plan="$(nix eval --json "${WORK}#nixosConfigurations.${host}.config.skadi.provision.secrets")"
  install -d -m0755 secrets
  : > secrets/secrets.yaml
  for name in $(jq -r 'keys[]' <<<"$plan"); do
    method=$(jq -r --arg n "$name" '.[$n].method'           <<<"$plan")
    prompt=$(jq -r --arg n "$name" '.[$n].prompt'           <<<"$plan")
    format=$(jq -r --arg n "$name" '.[$n].format'           <<<"$plan")
    optional=$(jq -r --arg n "$name" '.[$n].optional'       <<<"$plan")
    placeholder=$(jq -r --arg n "$name" '.[$n].placeholder' <<<"$plan")
    case "$method" in
      mkpasswd)    log "set the $name"; value=$(mkpasswd -m sha-512) ;;
      placeholder) value=$(jq -r --arg n "$name" '.[$n].value' <<<"$plan") ;;
      paste)
        read -r -p "paste $prompt: " raw
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

provision_secrets "$HOST"

# 4. copy flake to /persist/etc/skadi (impermanence-persisted) and install.
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
# which section 1c relocated onto the target disk. Two things matter here:
#   * NON-DIVERTED (note: NO `--store local`, NO `--store "local?root=/mnt"`):
#     realStoreDir == storeDir, so build + eval share one store -- gitTracked
#     stays git-aware and there's no unsigned cross-store copy. It also means
#     Lix does NOT auto-enable the sandbox for a diverted store; ours is on
#     because installer.nix asks for it.
#   * DISK-BACKED (via the 1c overlay): OUTPUTS land on /mnt, not the ISO's RAM
#     tmpfs, so a cold from-source build survives lean 8-16 GB machines. Build
#     SCRATCH is handled separately by build-dir=/mnt/nix-build-tmp in
#     installer.nix -- the daemon unpacks there, NOT under the client TMPDIR.
# Substituters + trusted keys now live in installer.nix (base + the desktop
# upstreams: Hyprland/walker/noctalia), so the daemon substitutes those with no
# inline --substituters here. Lix is deliberately NOT among them: its cargo
# target is the disk-pressure canary, so it builds from source every install --
# that's the point. notion-sync and the rest of the fleet closure build from
# source too; only third-party upstreams are fetched.
# 4a. basic disk resilience (see roadmap "Disk-pressure resilience"). NO Lix
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
#   installer.nix; section 1c gives the daemon a writable on-disk store. The old
#   logseq `EACCES ... unlink esbuild_*.tgz` was a build-user privilege artifact
#   of the root local-store build -- khion builds the identical drv fine as
#   nixbld, so building its way avoids it with no root build needed.
if ! SYS_PATH="$(nix build --no-link --print-out-paths \
  --max-jobs "$MAX_JOBS" --cores "$CORES" \
  --min-free "$MIN_FREE" --max-free "$MAX_FREE" \
  "${WORK}#nixosConfigurations.${HOST}.config.system.build.toplevel")"; then
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
