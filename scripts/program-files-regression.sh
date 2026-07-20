#!/usr/bin/env bash

# Runtime evidence stays outside the repo; only a verified healthy corpus is committed.
CACHE="${SKADI_PROGRAM_FILES_CACHE:-$HOME/.cache/skadi-program-files-regression}"
KITTY_REL=".config/kitty/kitty.conf"
KITTY_PATH="$HOME/$KITTY_REL"
mkdir -p "$CACHE"

log() { printf '[program-files-regression] %s\n' "$*"; }
die() { printf '[program-files-regression] ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'USAGE'
program-files-regression <command>

  desired --host <khion|lumi> --output <path>
  inventory --host <khion|lumi> --desired-output <path> --drift-output <path> [--healthy-output <path>]
  natural-prepare --host khion --drift <path>
  natural-assert --host khion --drift <path>
  restore --host khion --drift <path>
  assemble --khion <path> --lumi <path> --output <path>
  roots --host khion
  case-prepare --host khion --mode <absent|dangling|drifted>
  case-switch-assert --host khion --mode <absent|dangling|drifted>
  case-boot-assert --host khion --mode <absent|dangling|drifted>
  vm --flake <path>
USAGE
}

require_host() {
  local expected="$1" actual
  actual="$(hostnamectl --static 2>/dev/null || hostname)"
  [ "$actual" = "$expected" ] || die "command is for $expected, running on $actual"
}

system_toplevel() { readlink -f /run/current-system; }
content_hash() { sha256sum -- "$1" | awk '{print $1}'; }

home_generation() {
  # Integrated Home Manager has used both profile locations across generations.
  local candidate
  for candidate in "$HOME/.local/state/nix/profiles/home-manager" "$HOME/.nix-profile"; do
    if [ -e "$candidate" ] || [ -L "$candidate" ]; then
      readlink -f "$candidate"
      return
    fi
  done
  printf 'null\n'
}

home_persistence() {
  # A boot result means something different when .config lives on the rolled-back root.
  local mount
  mount="$(findmnt -T "$HOME/.config" -n -o SOURCE,FSROOT,TARGET 2>/dev/null || true)"
  if grep -Eq '(@persist|/persist)' <<<"$mount"; then
    printf 'persisted\n'
  else
    printf 'ephemeral-root\n'
  fi
}

entries() {
  # Keep declaration identity separate from volatile store paths in observed state.
  [ -n "${PROGRAM_FILES_MANIFEST:-}" ] || die "PROGRAM_FILES_MANIFEST is missing"
  jq -r '.entries[] | [.declarationIdentity, .destination, .sourceKind, (.sourcePath // "")] | @tsv' "$PROGRAM_FILES_MANIFEST"
}

store_object() {
  local path="$1"
  if [[ "$path" == /nix/store/* ]]; then
    printf '/nix/store/%s\n' "$(cut -d/ -f1 <<<"${path#/nix/store/}")"
  fi
}

desired_manifest() {
  # This path evaluates a host but never activates it, so lumi can be compared from khion.
  local host="$1" output="$2" desired_files desired_tmp declaration destination source_kind source_path desired_target desired_hash expected_type
  desired_files="$(mktemp)"
  desired_tmp="$(mktemp)"
  nix eval --json ".#nixosConfigurations.${host}.config.hjem.users.feltfomo.files" > "$desired_files"
  while IFS=$'\t' read -r declaration destination source_kind source_path; do
    if [ "$source_kind" = "activation-template" ]; then
      expected_type="regular"
      desired_target="$(readlink -f -- "$source_path")"
      [ -f "$desired_target" ] || die "desired template source missing: $source_path"
    else
      expected_type="symlink"
      desired_target="$(jq -r --arg destination "$destination" '.[$destination].source // empty' "$desired_files")"
      if [ -z "$desired_target" ]; then
        # Ownership may legitimately exclude an entry from this host's desired set.
        continue
      fi
      [ -e "$desired_target" ] || die "evaluation produced a missing source for $host:$destination"
    fi
    desired_hash="$(content_hash "$desired_target")"
    jq -cn \
      --arg declarationIdentity "$declaration" --arg destination "$destination" --arg sourceKind "$source_kind" \
      --arg contentSha256 "$desired_hash" --arg observedType "$expected_type" --arg desiredTarget "$desired_target" \
      --arg targetStoreObject "$(store_object "$desired_target")" \
      '{declarationIdentity:$declarationIdentity,destination:$destination,sourceKind:$sourceKind,contentSha256:$contentSha256,observedType:$observedType,linkTarget:(if $observedType=="symlink" then $desiredTarget else null end),resolvedTarget:$desiredTarget,targetStoreObject:(if $targetStoreObject=="" then null else $targetStoreObject end),authorityPrincipal:"user:feltfomo"}' >> "$desired_tmp"
  done < <(entries)
  jq -S -n --arg host "$host" --arg systemToplevel "$(nix eval --raw ".#nixosConfigurations.${host}.config.system.build.toplevel")" --slurpfile entries "$desired_tmp" \
    '{host:$host,systemToplevel:$systemToplevel,homeGeneration:null,homePersistence:null,entries:($entries|sort_by(.destination))}' > "$output"
  rm -f "$desired_files" "$desired_tmp"
  log "captured desired manifest for $host -> $output"
}

inventory() {
  # Desired and realized state are emitted independently so drift never pollutes parity data.
  local host="$1" desired_output="$2" drift_output="$3" healthy_output="$4"
  local desired_files desired_tmp drift_tmp declaration destination source_kind source_path
  local path expected_type desired_target desired_hash status observed_type raw_target resolved_target actual_hash actual_store
  require_host "$host"
  desired_files="$(mktemp)"
  desired_tmp="$(mktemp)"
  drift_tmp="$(mktemp)"
  nix eval --json ".#nixosConfigurations.${host}.config.hjem.users.feltfomo.files" > "$desired_files"

  while IFS=$'\t' read -r declaration destination source_kind source_path; do
    path="$HOME/$destination"
    if [ "$source_kind" = "activation-template" ]; then
      expected_type="regular"
      desired_target="$(readlink -f -- "$source_path")"
      [ -f "$desired_target" ] || die "desired template source missing: $source_path"
    else
      expected_type="symlink"
      desired_target="$(jq -r --arg destination "$destination" '.[$destination].source // empty' "$desired_files")"
      [ -n "$desired_target" ] && [ -e "$desired_target" ] || die "evaluation did not produce a live source for $destination"
    fi
    desired_hash="$(content_hash "$desired_target")"

    # Unknown shapes default to foreign; only proved representations may be repaired.
    status="foreign"
    observed_type="other"
    raw_target=""
    resolved_target=""
    actual_hash=""
    actual_store=""
    if [ "$expected_type" = "symlink" ]; then
      if [ -L "$path" ]; then
        observed_type="symlink"
        raw_target="$(readlink -- "$path")"
        resolved_target="$(readlink -f -- "$path" || true)"
        if [ -z "$resolved_target" ] || [ ! -e "$resolved_target" ]; then
          status="dangling"
        else
          actual_hash="$(content_hash "$path")"
          actual_store="$(store_object "$resolved_target")"
          if [ "$resolved_target" = "$desired_target" ] && [ "$actual_hash" = "$desired_hash" ]; then
            status="healthy"
          else
            status="drifted-target"
          fi
        fi
      elif [ ! -e "$path" ]; then
        observed_type="missing"
        status="missing"
      fi
    else
      if [ -L "$path" ]; then
        observed_type="symlink"
        raw_target="$(readlink -- "$path")"
        resolved_target="$(readlink -f -- "$path" || true)"
        status="foreign"
      elif [ -f "$path" ]; then
        observed_type="regular"
        resolved_target="$(readlink -f -- "$path")"
        actual_hash="$(content_hash "$path")"
        if [ "$actual_hash" = "$desired_hash" ]; then status="healthy"; else status="drifted-target"; fi
      elif [ ! -e "$path" ]; then
        observed_type="missing"
        status="missing"
      fi
    fi

    jq -cn \
      --arg declarationIdentity "$declaration" --arg destination "$destination" --arg sourceKind "$source_kind" \
      --arg contentSha256 "$desired_hash" --arg observedType "$expected_type" --arg desiredTarget "$desired_target" \
      --arg targetStoreObject "$(store_object "$desired_target")" \
      '{declarationIdentity:$declarationIdentity,destination:$destination,sourceKind:$sourceKind,contentSha256:$contentSha256,observedType:$observedType,linkTarget:(if $observedType=="symlink" then $desiredTarget else null end),resolvedTarget:$desiredTarget,targetStoreObject:(if $targetStoreObject=="" then null else $targetStoreObject end),authorityPrincipal:"user:feltfomo"}' >> "$desired_tmp"
    jq -cn \
      --arg declarationIdentity "$declaration" --arg destination "$destination" --arg sourceKind "$source_kind" \
      --arg status "$status" --arg expectedType "$expected_type" --arg observedType "$observed_type" \
      --arg desiredTarget "$desired_target" --arg desiredHash "$desired_hash" --arg rawTarget "$raw_target" \
      --arg resolvedTarget "$resolved_target" --arg actualHash "$actual_hash" --arg actualStoreObject "$actual_store" \
      '{declarationIdentity:$declarationIdentity,destination:$destination,sourceKind:$sourceKind,status:$status,expectedType:$expectedType,observedType:$observedType,desiredTarget:$desiredTarget,desiredContentSha256:$desiredHash,rawTarget:(if $rawTarget=="" then null else $rawTarget end),resolvedTarget:(if $resolvedTarget=="" then null else $resolvedTarget end),actualContentSha256:(if $actualHash=="" then null else $actualHash end),actualStoreObject:(if $actualStoreObject=="" then null else $actualStoreObject end)}' >> "$drift_tmp"
  done < <(entries)

  local generation persistence drift_count
  generation="$(home_generation)"
  persistence="$(home_persistence)"
  jq -S -n --arg host "$host" --arg systemToplevel "$(system_toplevel)" --arg homeGeneration "$generation" --arg homePersistence "$persistence" --slurpfile entries "$desired_tmp" \
    '{host:$host,systemToplevel:$systemToplevel,homeGeneration:(if $homeGeneration=="null" then null else $homeGeneration end),homePersistence:$homePersistence,entries:($entries|sort_by(.destination))}' > "$desired_output"
  jq -S -n --arg host "$host" --arg systemToplevel "$(system_toplevel)" --arg homePersistence "$persistence" --slurpfile entries "$drift_tmp" \
    '{host:$host,systemToplevel:$systemToplevel,homePersistence:$homePersistence,entries:($entries|sort_by(.destination)),summary:($entries|group_by(.status)|map({key:.[0].status,value:length})|from_entries)}' > "$drift_output"
  drift_count="$(jq '[.entries[]|select(.status!="healthy")]|length' "$drift_output")"
  rm -f "$desired_files" "$desired_tmp" "$drift_tmp"

  if [ "$drift_count" -ne 0 ]; then
    # Keep scanning evidence useful while refusing to bless any unhealthy corpus.
    [ -z "$healthy_output" ] || rm -f "$healthy_output"
    log "$host inventory found $drift_count unhealthy entries; desired baseline and drift report emitted"
    return 1
  fi
  if [ -n "$healthy_output" ]; then cp "$desired_output" "$healthy_output"; fi
  log "$host inventory is healthy"
}

natural_prepare() {
  local host="$1" drift="$2"
  require_host "$host"
  [ "$(jq '[.entries[]|select(.status!="healthy")]|length' "$drift")" -gt 0 ] || die "natural repro needs existing drift"
  cp "$drift" "$CACHE/natural-drift-before.json"
  jq -n --arg systemToplevel "$(system_toplevel)" '{systemToplevel:$systemToplevel}' > "$CACHE/natural-state.json"
  log "recorded natural drift before the no-op switch"
}

natural_assert() {
  # Destination, failure class, and raw target must all survive to count as non-repair.
  local host="$1" drift="$2" before after before_set after_set
  require_host "$host"
  before="$(jq -r .systemToplevel "$CACHE/natural-state.json")"
  after="$(system_toplevel)"
  [ "$before" = "$after" ] || die "switch changed the toplevel: $before -> $after"
  before_set="$(jq -Sc '[.entries[]|select(.status!="healthy")|{destination,status,rawTarget}]' "$CACHE/natural-drift-before.json")"
  after_set="$(jq -Sc '[.entries[]|select(.status!="healthy")|{destination,status,rawTarget}]' "$drift")"
  [ "$before_set" = "$after_set" ] || die "natural drift changed across the no-op switch"
  jq -n --arg before "$before" --arg after "$after" --argjson drift "$(jq '[.entries[]|select(.status!="healthy")]' "$drift")" \
    '{systemToplevelBefore:$before,systemToplevelAfter:$after,byteIdenticalToplevel:($before==$after),unrepairedDrift:$drift}' > "$CACHE/natural-non-repair-evidence.json"
  log "natural drift survived a byte-identical no-op switch"
}

restore_drift() {
  # Equality isn't ownership proof; a foreign entry is never test setup to overwrite.
  local host="$1" drift="$2" destination status expected_type desired_target path
  require_host "$host"
  if jq -e '.entries[]|select(.status=="foreign")' "$drift" >/dev/null; then
    die "foreign entries require manual review; refusing restoration"
  fi
  while IFS=$'\t' read -r destination status expected_type desired_target; do
    [ "$status" != "healthy" ] || continue
    path="$HOME/$destination"
    mkdir -p "$(dirname "$path")"
    if [ "$expected_type" = "symlink" ]; then
      if [ -e "$path" ] && [ ! -L "$path" ]; then die "refusing to replace real file: $destination"; fi
      ln -sfn -- "$desired_target" "$path"
    else
      if [ -L "$path" ] || { [ -e "$path" ] && [ ! -f "$path" ]; }; then die "refusing to replace foreign entry: $destination"; fi
      install -m 0644 -- "$desired_target" "$path"
    fi
  done < <(jq -r '.entries[]|[.destination,.status,.expectedType,.desiredTarget]|@tsv' "$drift")
  log "restored non-foreign drift to current desired targets"
}

assemble() {
  # Failure evidence remains in CACHE; this file is the healthy SP8 parity target.
  local khion="$1" lumi="$2" output="$3"
  if [ -n "$lumi" ]; then
    jq -S -n --slurpfile khion "$khion" --slurpfile lumi "$lumi" \
      '{schemaVersion:1,generatedBy:"program-files-regression/v1",schemaComment:"Migration parity keys on declarationIdentity, destination, sourceKind, contentSha256, and observedType; systemToplevel and homeGeneration are provenance only.",hashAlgorithm:"sha256",hosts:{khion:$khion[0],lumi:$lumi[0]}}' > "$output"
  else
    jq -S -n --slurpfile khion "$khion" \
      '{schemaVersion:1,generatedBy:"program-files-regression/v1",schemaComment:"Migration parity keys on declarationIdentity, destination, sourceKind, contentSha256, and observedType; systemToplevel and homeGeneration are provenance only.",hashAlgorithm:"sha256",hosts:{khion:$khion[0]}}' > "$output"
  fi
  jq -e '.hosts.khion.host=="khion"' "$output" >/dev/null
  log "assembled corpus -> $output"
}

matrix_path() { printf '%s/repair-matrix.json\n' "$CACHE"; }

ensure_matrix() {
  # Null cells make an interrupted matrix obvious instead of looking like a pass.
  local matrix
  matrix="$(matrix_path)"
  if [ ! -f "$matrix" ]; then
    jq -n '{absent:{"no-op-switch":null,reboot:null},dangling:{"no-op-switch":null,reboot:null},drifted:{"no-op-switch":null,reboot:null}}' > "$matrix"
  fi
}

record_matrix() {
  local mode="$1" column="$2" outcome="$3" matrix tmp
  ensure_matrix
  matrix="$(matrix_path)"
  tmp="${matrix}.tmp"
  jq --arg mode "$mode" --arg column "$column" --arg outcome "$outcome" '.[$mode][$column]=$outcome' "$matrix" > "$tmp"
  mv "$tmp" "$matrix"
}

save_case_state() {
  local mode="$1" file="$2" raw resolved hash
  [ -L "$KITTY_PATH" ] || die "$KITTY_PATH is not a healthy owned symlink"
  raw="$(readlink -- "$KITTY_PATH")"
  resolved="$(readlink -f -- "$KITTY_PATH")"
  [ -e "$resolved" ] || die "$KITTY_PATH is already dangling"
  hash="$(content_hash "$KITTY_PATH")"
  jq -n --arg mode "$mode" --arg path "$KITTY_PATH" --arg rawTarget "$raw" --arg resolvedTarget "$resolved" --arg contentSha256 "$hash" --arg systemToplevel "$(system_toplevel)" --arg bootId "$(cat /proc/sys/kernel/random/boot_id)" --arg homePersistence "$(home_persistence)" '{mode:$mode,path:$path,rawTarget:$rawTarget,resolvedTarget:$resolvedTarget,contentSha256:$contentSha256,systemToplevel:$systemToplevel,bootId:$bootId,homePersistence:$homePersistence}' > "$file"
}

restore_kitty() {
  local state="$1" raw expected_hash
  raw="$(jq -r .rawTarget "$state")"
  expected_hash="$(jq -r .contentSha256 "$state")"
  rm -f -- "$KITTY_PATH"
  ln -s -- "$raw" "$KITTY_PATH"
  [ "$(content_hash "$KITTY_PATH")" = "$expected_hash" ] || die "kitty restoration hash mismatch"
}

case_prepare() {
  # The three states expose the backend's missing-versus-invalid-presence behavior.
  local host="$1" mode="$2" state fixture manufactured
  require_host "$host"
  case "$mode" in absent|dangling|drifted) ;; *) die "unknown repair-matrix mode: $mode";; esac
  state="$CACHE/case-${mode}-state.json"
  save_case_state "$mode" "$state"
  case "$mode" in
    absent)
      rm -- "$KITTY_PATH"
      ;;
    dangling)
      # Delete a real store object first; a made-up path wouldn't prove GC-shaped drift.
      fixture="$CACHE/dangling-fixture"
      printf 'removed kitty target fixture\n' > "$fixture"
      manufactured="$(nix store add-file "$fixture")"
      nix-store --delete "$manufactured" >/dev/null
      [ ! -e "$manufactured" ] || die "could not remove dangling fixture target"
      ln -sfn -- "$manufactured" "$KITTY_PATH"
      ;;
    drifted)
      # Keep this object live so the drifted case can't collapse into the dangling case.
      fixture="$CACHE/drifted-fixture"
      printf 'wrong kitty content fixture\n' > "$fixture"
      manufactured="$(nix store add-file "$fixture")"
      [ -e "$manufactured" ] || die "could not create drifted fixture target"
      [ "$(content_hash "$manufactured")" != "$(jq -r .contentSha256 "$state")" ] || die "drifted fixture unexpectedly matches desired content"
      ln -sfn -- "$manufactured" "$KITTY_PATH"
      ;;
  esac
  jq --arg manufacturedTarget "$(readlink -- "$KITTY_PATH" 2>/dev/null || true)" '. + {manufacturedTarget:$manufacturedTarget}' "$state" > "${state}.tmp"
  mv "${state}.tmp" "$state"
  log "prepared $mode kitty state at boot ID $(jq -r .bootId "$state")"
}

case_outcome() {
  # Repair requires both the expected target identity and its exact bytes.
  local state="$1" expected_target expected_hash
  expected_target="$(jq -r .resolvedTarget "$state")"
  expected_hash="$(jq -r .contentSha256 "$state")"
  if [ -L "$KITTY_PATH" ] && [ "$(readlink -f -- "$KITTY_PATH" || true)" = "$expected_target" ] && [ "$(content_hash "$KITTY_PATH" 2>/dev/null || true)" = "$expected_hash" ]; then
    printf 'repaired\n'
  else
    printf 'not-repaired\n'
  fi
}

case_switch_assert() {
  local host="$1" mode="$2" state before after outcome manufactured
  require_host "$host"
  state="$CACHE/case-${mode}-state.json"
  [ -f "$state" ] || die "case state is missing for $mode"
  before="$(jq -r .systemToplevel "$state")"
  after="$(system_toplevel)"
  [ "$before" = "$after" ] || die "switch changed the toplevel: $before -> $after"
  outcome="$(case_outcome "$state")"
  manufactured="$(jq -r .manufacturedTarget "$state")"
  if [ "$mode" = absent ]; then
    [ "$outcome" = repaired ] || die "absent kitty.conf was not repaired"
  else
    [ "$outcome" = not-repaired ] || die "$mode kitty.conf was unexpectedly repaired"
    [ -L "$KITTY_PATH" ] && [ "$(readlink -- "$KITTY_PATH")" = "$manufactured" ] || die "$mode fixture changed instead of remaining invalid"
  fi
  record_matrix "$mode" "no-op-switch" "$outcome"
  jq -n --arg mode "$mode" --arg before "$before" --arg after "$after" --arg outcome "$outcome" --arg manufacturedTarget "$manufactured" '{mode:$mode,systemToplevelBefore:$before,systemToplevelAfter:$after,byteIdenticalToplevel:($before==$after),outcome:$outcome,manufacturedTarget:$manufacturedTarget}' > "$CACHE/case-${mode}-switch-evidence.json"
  if [ "$outcome" != repaired ]; then restore_kitty "$state"; fi
  [ "$(case_outcome "$state")" = repaired ] || die "failed to restore healthy kitty.conf"
  log "$mode no-op switch outcome: $outcome; healthy state verified"
}

case_boot_assert() {
  # A changed boot ID prevents a second shell invocation from masquerading as reboot proof.
  local host="$1" mode="$2" state before after outcome
  require_host "$host"
  state="$CACHE/case-${mode}-state.json"
  [ -f "$state" ] || die "case state is missing for $mode"
  before="$(jq -r .bootId "$state")"
  after="$(cat /proc/sys/kernel/random/boot_id)"
  [ "$before" != "$after" ] || die "boot ID did not change"
  outcome="$(case_outcome "$state")"
  record_matrix "$mode" reboot "$outcome"
  if [ "$outcome" != repaired ]; then restore_kitty "$state"; fi
  [ "$(case_outcome "$state")" = repaired ] || die "failed to restore healthy kitty.conf"
  jq -n --arg mode "$mode" --arg bootIdBefore "$before" --arg bootIdAfter "$after" --arg outcome "$outcome" --arg homePersistence "$(jq -r .homePersistence "$state")" '{mode:$mode,bootIdBefore:$bootIdBefore,bootIdAfter:$bootIdAfter,bootIdChanged:($bootIdBefore!=$bootIdAfter),outcome:$outcome,homePersistence:$homePersistence,healthyStateRestored:true}' > "$CACHE/case-${mode}-boot-evidence.json"
  log "$mode reboot outcome: $outcome; healthy state verified"
}

roots_check() {
  # A live target isn't retention evidence until an active root reaches it.
  require_host khion
  [ -L "$KITTY_PATH" ] || die "kitty.conf is not a symlink"
  local target roots
  target="$(readlink -f -- "$KITTY_PATH")"
  roots="$(nix-store -q --roots "$target" 2>/dev/null || true)"
  [ -n "$roots" ] || die "no GC root reaches $target"
  printf '%s\n' "$roots" > "$CACHE/khion-kitty-roots.txt"
  log "active roots retain $target"
}

ssh_vm() {
  ssh -i "$VM_KEY" -p "$VM_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=5 root@localhost "$@"
}

vm_proof() {
  # Destructive generation GC and declaration removal stay off the workstation.
  local flake="$1"
  command -v nix >/dev/null || die "nix is required"
  [ -n "${OVMF_FD:-}" ] || die "OVMF_FD is missing"
  local vm_cache="${SKADI_VM_CACHE:-$HOME/.cache/skadi-vm}"
  VM_KEY="$vm_cache/vm-test-key"
  VM_PORT=2222
  [ -f "$VM_KEY" ] || die "missing $VM_KEY"
  # The installer harness is intentionally cold; this is a one-time disposable proof path.
  log "installing disposable vm through the existing vm-test harness"
  nix run "${flake}#vm-test" -- --host vm --reset --keep

  local disk="$vm_cache/vm.qcow2" vars="$vm_cache/vm-vars.fd" serial="$CACHE/vm-regression-serial.log"
  local code="$OVMF_FD/FV/OVMF_CODE.fd"
  [ -f "$disk" ] && [ -f "$vars" ] && [ -f "$code" ] || die "vm artifacts are incomplete"
  : > "$serial"
  qemu-system-x86_64 -machine q35,accel=kvm -cpu host -m 8192 -smp 4 \
    -drive "if=pflash,format=raw,readonly=on,file=$code" \
    -drive "if=pflash,format=raw,file=$vars" \
    -drive "file=$disk,if=virtio,format=qcow2" \
    -netdev "user,id=net0,hostfwd=tcp::$VM_PORT-:22" -device virtio-net,netdev=net0 \
    -display none -serial "file:$serial" -no-reboot -boot order=c &
  local qemu_pid=$!
  trap 'kill "$qemu_pid" 2>/dev/null || true; wait "$qemu_pid" 2>/dev/null || true' RETURN
  local up=0
  for _ in $(seq 1 60); do
    if ssh_vm true 2>/dev/null; then up=1; break; fi
    kill -0 "$qemu_pid" 2>/dev/null || die "VM exited before SSH; see $serial"
    sleep 5
  done
  [ "$up" = 1 ] || die "VM did not accept SSH"

  # Everything below mutates only the installed guest checkout and store.
  ssh_vm 'bash -s' <<'REMOTE'
set -euo pipefail
cd /etc/skadi
link=/home/feltfomo/.config/kitty/kitty.conf
[ -L "$link" ]
old_target=$(readlink -f "$link")
printf '\n# disposable retention generation\n' >> configs/kitty/kitty.conf
nixos-rebuild switch --flake /etc/skadi#vm
new_target=$(readlink -f "$link")
[ "$old_target" != "$new_target" ]
[ -e "$new_target" ]
nix-collect-garbage -d
[ ! -e "$old_target" ]
[ -e "$new_target" ]
retention_hash=$(sha256sum "$link" | awk '{print $1}')
sed -i '/^[[:space:]]*kitty[[:space:]]*$/d' modules/users/feltfomo.nix
declared=$(nix eval --raw .#nixosConfigurations.vm.config.hjem.users.feltfomo.files --apply 'files: if builtins.hasAttr ".config/kitty/kitty.conf" files then "present" else "absent"')
[ "$declared" = absent ]
nixos-rebuild switch --flake /etc/skadi#vm
[ -L "$link" ]
cleanup_target=$(readlink -f "$link")
jq -n --arg oldTarget "$old_target" --arg currentTarget "$new_target" --arg retentionHash "$retention_hash" --arg cleanupTarget "$cleanup_target" '{retention:{oldTarget:$oldTarget,oldTargetReaped:true,currentTarget:$currentTarget,currentTargetSurvived:true,currentContentSha256:$retentionHash},cleanup:{declarationAbsentFromEvaluation:true,staleEntryRemained:true,observedTarget:$cleanupTarget}}' > /tmp/program-files-vm-evidence.json
REMOTE
  scp -i "$VM_KEY" -P "$VM_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR root@localhost:/tmp/program-files-vm-evidence.json "$CACHE/vm-evidence.json"
  jq . "$CACHE/vm-evidence.json"
  log "VM retention and cleanup evidence captured"
}

command="${1:-}"
shift || true
case "$command" in
  desired)
    host=""; output=""
    while [ "$#" -gt 0 ]; do case "$1" in --host) host="$2"; shift 2;; --output) output="$2"; shift 2;; *) die "unknown desired argument: $1";; esac; done
    [ -n "$host" ] && [ -n "$output" ] || die "desired needs --host and --output"
    desired_manifest "$host" "$output"
    ;;
  inventory)
    host=""; desired_output=""; drift_output=""; healthy_output=""
    while [ "$#" -gt 0 ]; do case "$1" in --host) host="$2"; shift 2;; --desired-output) desired_output="$2"; shift 2;; --drift-output) drift_output="$2"; shift 2;; --healthy-output) healthy_output="$2"; shift 2;; *) die "unknown inventory argument: $1";; esac; done
    [ -n "$host" ] && [ -n "$desired_output" ] && [ -n "$drift_output" ] || die "inventory needs --host, --desired-output, and --drift-output"
    inventory "$host" "$desired_output" "$drift_output" "$healthy_output"
    ;;
  natural-prepare)
    [ "${1:-}" = --host ] && [ -n "${2:-}" ] && [ "${3:-}" = --drift ] && [ -n "${4:-}" ] || die "natural-prepare needs --host and --drift"
    natural_prepare "$2" "$4";;
  natural-assert)
    [ "${1:-}" = --host ] && [ -n "${2:-}" ] && [ "${3:-}" = --drift ] && [ -n "${4:-}" ] || die "natural-assert needs --host and --drift"
    natural_assert "$2" "$4";;
  restore)
    [ "${1:-}" = --host ] && [ -n "${2:-}" ] && [ "${3:-}" = --drift ] && [ -n "${4:-}" ] || die "restore needs --host and --drift"
    restore_drift "$2" "$4";;
  assemble)
    khion=""; lumi=""; output=""
    while [ "$#" -gt 0 ]; do case "$1" in --khion) khion="$2"; shift 2;; --lumi) lumi="$2"; shift 2;; --output) output="$2"; shift 2;; *) die "unknown assemble argument: $1";; esac; done
    [ -n "$khion" ] && [ -n "$output" ] || die "assemble needs --khion and --output"
    assemble "$khion" "$lumi" "$output"
    ;;
  roots) [ "${1:-}" = --host ] && [ "${2:-}" = khion ] || die "roots requires --host khion"; roots_check;;
  case-prepare)
    [ "${1:-}" = --host ] && [ -n "${2:-}" ] && [ "${3:-}" = --mode ] && [ -n "${4:-}" ] || die "case-prepare needs --host and --mode"
    case_prepare "$2" "$4";;
  case-switch-assert)
    [ "${1:-}" = --host ] && [ -n "${2:-}" ] && [ "${3:-}" = --mode ] && [ -n "${4:-}" ] || die "case-switch-assert needs --host and --mode"
    case_switch_assert "$2" "$4";;
  case-boot-assert)
    [ "${1:-}" = --host ] && [ -n "${2:-}" ] && [ "${3:-}" = --mode ] && [ -n "${4:-}" ] || die "case-boot-assert needs --host and --mode"
    case_boot_assert "$2" "$4";;
  vm)
    flake="."
    while [ "$#" -gt 0 ]; do case "$1" in --flake) flake="$2"; shift 2;; *) die "unknown vm argument: $1";; esac; done
    vm_proof "$flake"
    ;;
  -h|--help|help) usage;;
  *) usage; exit 2;;
esac
