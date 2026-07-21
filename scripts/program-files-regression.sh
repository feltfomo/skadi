#!/usr/bin/env bash

# Runtime evidence stays outside the repo; baselines contain only healthy state.
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
  vm provision --flake <path>
  vm run --flake <path> --khion-matrix <path>
  reboot-prepare --host vm --mode <absent|dangling|drifted> --run-id <id>
  reboot-assert --host vm --mode <absent|dangling|drifted> --run-id <id>
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
    die "foreign entries aren't owned by this harness; refusing restoration"
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
  # Failure evidence stays in CACHE; assembled output contains only healthy parity data.
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
  local host="$1" mode="$2" state before after outcome manufactured fixture_valid expected_hash
  require_host "$host"
  state="$CACHE/case-${mode}-state.json"
  [ -f "$state" ] || die "case state is missing for $mode"
  before="$(jq -r .bootId "$state")"
  after="$(cat /proc/sys/kernel/random/boot_id)"
  [ "$before" != "$after" ] || die "boot ID did not change"
  outcome="$(case_outcome "$state")"
  record_matrix "$mode" reboot "$outcome"
  if [ "$host" = vm ]; then
    manufactured="$(jq -r .manufacturedTarget "$state")"
    expected_hash="$(jq -r .contentSha256 "$state")"
    fixture_valid=true
    case "$mode" in
      absent) [ "$outcome" = repaired ] || fixture_valid=false ;;
      dangling) [ -L "$KITTY_PATH" ] && [ "$(readlink -- "$KITTY_PATH")" = "$manufactured" ] && [ ! -e "$manufactured" ] || fixture_valid=false ;;
      drifted) [ -L "$KITTY_PATH" ] && [ "$(readlink -- "$KITTY_PATH")" = "$manufactured" ] && [ -e "$manufactured" ] && [ "$(content_hash "$manufactured")" != "$expected_hash" ] || fixture_valid=false ;;
    esac
    [ "$fixture_valid" = true ] || die "$mode fixture changed shape across reboot"
  fi
  if [ "$outcome" != repaired ]; then restore_kitty "$state"; fi
  [ "$(case_outcome "$state")" = repaired ] || die "failed to restore healthy kitty.conf"
  if [ "$host" = vm ]; then
    jq -n --arg mode "$mode" --arg bootIdBefore "$before" --arg bootIdAfter "$after" --arg outcome "$outcome" \
      --arg homePersistence "$(jq -r .homePersistence "$state")" --arg manufacturedTarget "$manufactured" \
      --argjson fixtureStateValid "$fixture_valid" \
      '{mode:$mode,bootIdBefore:$bootIdBefore,bootIdAfter:$bootIdAfter,bootIdChanged:($bootIdBefore!=$bootIdAfter),outcome:$outcome,homePersistence:$homePersistence,manufacturedTarget:$manufacturedTarget,fixtureStateValid:$fixtureStateValid,healthyStateRestored:true}' \
      > "$CACHE/case-${mode}-boot-evidence.json"
  else
    jq -n --arg mode "$mode" --arg bootIdBefore "$before" --arg bootIdAfter "$after" --arg outcome "$outcome" --arg homePersistence "$(jq -r .homePersistence "$state")" '{mode:$mode,bootIdBefore:$bootIdBefore,bootIdAfter:$bootIdAfter,bootIdChanged:($bootIdBefore!=$bootIdAfter),outcome:$outcome,homePersistence:$homePersistence,healthyStateRestored:true}' > "$CACHE/case-${mode}-boot-evidence.json"
  fi
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

expected_matrix() {
  jq -n '{absent:{"no-op-switch":"repaired",reboot:"repaired"},dangling:{"no-op-switch":"not-repaired",reboot:"not-repaired"},drifted:{"no-op-switch":"not-repaired",reboot:"not-repaired"}}'
}

normalize_matrix() {
  jq -S '{absent:{"no-op-switch":.absent["no-op-switch"],reboot:.absent.reboot},dangling:{"no-op-switch":.dangling["no-op-switch"],reboot:.dangling.reboot},drifted:{"no-op-switch":.drifted["no-op-switch"],reboot:.drifted.reboot}}' "$1"
}

reboot_prepare() {
  local host="$1" mode="$2" run_id="$3" sentinel state
  sentinel="$CACHE/vm-run-sentinel"
  state="$CACHE/case-${mode}-persistence-state.json"
  require_host "$host"
  if [ ! -f "$sentinel" ]; then printf '%s\n' "$run_id" > "$sentinel"; fi
  [ "$(cat "$sentinel")" = "$run_id" ] || die "persisted run sentinel changed"
  printf '%s\n' "$run_id:$mode" > "/root/program-files-regression-${mode}-root-marker"
  find "$CACHE" -maxdepth 1 -type f -name '*.json' ! -name 'case-*-persistence-state.json' -print0 \
    | sort -z | xargs -0 sha256sum > "$CACHE/case-${mode}-persisted-files.sha256"
  jq -n --arg runId "$run_id" --arg mode "$mode" --arg sentinelHash "$(content_hash "$sentinel")" \
    --arg evidenceSetHash "$(content_hash "$CACHE/case-${mode}-persisted-files.sha256")" \
    --arg bootId "$(cat /proc/sys/kernel/random/boot_id)" \
    '{runId:$runId,mode:$mode,sentinelHash:$sentinelHash,evidenceSetHash:$evidenceSetHash,bootId:$bootId}' > "$state"
  log "prepared persistence controls for $mode"
}

reboot_assert() {
  local host="$1" mode="$2" run_id="$3" sentinel state
  sentinel="$CACHE/vm-run-sentinel"
  state="$CACHE/case-${mode}-persistence-state.json"
  local marker="/root/program-files-regression-${mode}-root-marker" before after sentinel_hash
  require_host "$host"
  [ -f "$state" ] || die "persistence state is missing for $mode"
  [ -f "$sentinel" ] || die "persisted run sentinel disappeared"
  [ "$(cat "$sentinel")" = "$run_id" ] || die "persisted run sentinel changed"
  [ ! -e "$marker" ] || die "rolled-back root marker survived reboot"
  sentinel_hash="$(content_hash "$sentinel")"
  [ "$sentinel_hash" = "$(jq -r .sentinelHash "$state")" ] || die "persisted run sentinel hash changed"
  [ "$(content_hash "$CACHE/case-${mode}-persisted-files.sha256")" = "$(jq -r .evidenceSetHash "$state")" ] || die "persisted evidence manifest changed"
  sha256sum -c "$CACHE/case-${mode}-persisted-files.sha256" >/dev/null || die "persisted evidence changed or disappeared"
  before="$(jq -r .bootId "$state")"
  after="$(cat /proc/sys/kernel/random/boot_id)"
  [ "$before" != "$after" ] || die "boot ID did not change for persistence control"
  jq -n --arg runId "$run_id" --arg mode "$mode" --arg before "$before" --arg after "$after" \
    --arg sentinelHash "$sentinel_hash" \
    '{runId:$runId,mode:$mode,bootIdBefore:$before,bootIdAfter:$after,bootIdChanged:($before!=$after),persistedSentinelSurvived:true,persistedSentinelUnchanged:true,persistedEvidenceSetSurvived:true,rolledBackRootMarkerVanished:true,negativeControlPassed:true}' \
    > "$CACHE/case-${mode}-persistence-evidence.json"
  log "$mode persistence and rollback controls passed"
}

ssh_vm() {
  ssh -i "$VM_KEY" -p "$VM_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=5 "$VM_USER@localhost" "$@"
}

ssh_root() {
  local command
  printf -v command '%q ' "$@"
  ssh_vm "printf '%s\n' '$VM_SUDO_PASSWORD' | sudo -S -p '' -- $command"
}

scp_from_vm() {
  scp -i "$VM_KEY" -P "$VM_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR "$@"
}

vm_paths() {
  VM_CACHE="${SKADI_VM_CACHE:-$HOME/.cache/skadi-vm}"
  VM_KEY="${SKADI_PROGRAM_FILES_VM_KEY:-$HOME/.ssh/id_ed25519}"
  VM_USER="${SKADI_PROGRAM_FILES_VM_USER:-feltfomo}"
  VM_SUDO_PASSWORD="${SKADI_PROGRAM_FILES_VM_SUDO_PASSWORD:-skadi}"
  VM_PORT="${SKADI_PROGRAM_FILES_VM_PORT:-2222}"
  VM_BASE="$VM_CACHE/program-files-base.qcow2"
  VM_BASE_VARS="$VM_CACHE/program-files-base-vars.fd"
  VM_PROVISION="$VM_CACHE/program-files-base.json"
}

vm_require_common() {
  command -v nix >/dev/null || die "nix is required"
  [ -n "${OVMF_FD:-}" ] || die "OVMF_FD is missing"
  vm_paths
  mkdir -p "$VM_CACHE"
}

vm_require_run() {
  vm_require_common
  [ -f "$VM_KEY" ] || die "missing installed-VM key at $VM_KEY"
  chmod 600 "$VM_KEY" 2>/dev/null || true
}

vm_provision() {
  local flake="$1" installed_disk installed_vars tmp_disk tmp_vars
  vm_require_common
  [ ! -e "$VM_BASE" ] || die "base already exists at $VM_BASE; remove it explicitly before reprovisioning"
  installed_disk="$VM_CACHE/vm.qcow2"
  installed_vars="$VM_CACHE/vm-vars.fd"
  log "provisioning the lifecycle base through the installer harness"
  nix run "${flake}#vm-test" -- --host vm --reset --keep
  [ -f "$installed_disk" ] && [ -f "$installed_vars" ] || die "installer harness did not leave complete VM artifacts"
  tmp_disk="${VM_BASE}.tmp"
  tmp_vars="${VM_BASE_VARS}.tmp"
  cp --reflink=auto --sparse=always "$installed_disk" "$tmp_disk"
  cp "$installed_vars" "$tmp_vars"
  chmod 0444 "$tmp_disk" "$tmp_vars"
  mv "$tmp_disk" "$VM_BASE"
  mv "$tmp_vars" "$VM_BASE_VARS"
  jq -n --arg flake "$flake" --arg disk "$VM_BASE" --arg vars "$VM_BASE_VARS" \
    --arg createdAt "$(date --iso-8601=seconds)" \
    '{schemaVersion:1,flake:$flake,disk:$disk,ovmfVariables:$vars,createdAt:$createdAt}' > "$VM_PROVISION"
  log "provisioned immutable lifecycle base at $VM_BASE"
}

vm_wait_ssh() {
  local up=0
  for _ in $(seq 1 60); do
    if ssh_vm true 2>/dev/null; then up=1; break; fi
    kill -0 "$QEMU_PID" 2>/dev/null || die "VM exited before SSH; see $VM_SERIAL"
    sleep 5
  done
  [ "$up" = 1 ] || die "VM did not accept SSH"
}

vm_start() {
  : > "$VM_SERIAL"
  qemu-system-x86_64 -machine q35,accel=kvm -cpu host -m 8192 -smp 4 \
    -drive "if=pflash,format=raw,readonly=on,file=$VM_CODE" \
    -drive "if=pflash,format=raw,file=$VM_RUN_VARS" \
    -drive "file=$VM_OVERLAY,if=virtio,format=qcow2" \
    -netdev "user,id=net0,hostfwd=tcp::$VM_PORT-:22" -device virtio-net,netdev=net0 \
    -display none -serial "file:$VM_SERIAL" -no-reboot -boot order=c &
  QEMU_PID=$!
  vm_wait_ssh
}

vm_stop() {
  if [ -n "${QEMU_PID:-}" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
  QEMU_PID=""
}

vm_reboot() {
  ssh_root reboot >/dev/null 2>&1 || true
  wait "$QEMU_PID" 2>/dev/null || true
  QEMU_PID=""
  vm_start
}

vm_guest_harness() {
  ssh_vm env HOME=/home/feltfomo SKADI_PROGRAM_FILES_CACHE=/home/feltfomo/.cache/skadi-program-files-regression "$VM_APP/bin/program-files-regression" "$@"
}

vm_guest_harness_root() {
  ssh_root env HOME=/home/feltfomo SKADI_PROGRAM_FILES_CACHE=/home/feltfomo/.cache/skadi-program-files-regression "$VM_APP/bin/program-files-regression" "$@"
}

vm_prepare_test_flake() {
  local flake="$1" destination="$2" relative password_state source_file guest_hash host_hash copied
  git -C "$flake" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || die "VM test source must be a Git worktree: $flake"
  mkdir -p "$destination"
  (
    cd "$flake"
    git ls-files -z | tar --null -T - -cf -
  ) | tar -C "$destination" -xf -

  password_state="$(ssh_root getent shadow "$VM_USER" | cut -d: -f2)"
  [ -n "$password_state" ] && [[ "$password_state" != '!'* ]] \
    || die "installed VM account is locked or has no password hash"

  copied=0
  for source_file in "$destination"/secrets/*.yaml; do
    [ -f "$source_file" ] || continue
    relative="${source_file#"$destination"/}"
    ssh_vm test -f "/etc/skadi/$relative" \
      || die "installed VM is missing disposable encrypted source: $relative"
    scp_from_vm "$VM_USER@localhost:/etc/skadi/$relative" "$source_file"
    guest_hash="$(ssh_vm sha256sum "/etc/skadi/$relative" | awk '{print $1}')"
    host_hash="$(sha256sum "$source_file" | awk '{print $1}')"
    [ "$guest_hash" = "$host_hash" ] \
      || die "disposable encrypted source copy did not verify: $relative"
    copied=$((copied + 1))
  done
  [ "$copied" -gt 0 ] || die "tracked source contains no SOPS yaml files to replace"

  git -C "$destination" init -q
  git -C "$destination" add -A
  git -C "$destination" -c user.name=program-files-regression \
    -c user.email=program-files-regression@invalid commit -qm "disposable VM test source"
}

vm_copy_closures() {
  local ssh_opts
  ssh_opts="-i $VM_KEY -p $VM_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
  env NIX_SSHOPTS="$ssh_opts" nix copy --no-check-sigs --to "ssh-ng://$VM_USER@localhost" "$VM_TOPLEVEL" "$VM_APP" "$VM_ARCHIVE"
  ssh_root mkdir -p /nix/var/nix/gcroots/program-files-regression
  ssh_root ln -sfn "$VM_TOPLEVEL" /nix/var/nix/gcroots/program-files-regression/system
  ssh_root ln -sfn "$VM_APP" /nix/var/nix/gcroots/program-files-regression/harness
  ssh_root ln -sfn "$VM_ARCHIVE" /nix/var/nix/gcroots/program-files-regression/source
}

vm_select_toplevel() {
  ssh_root nix-env -p /nix/var/nix/profiles/system --set "$VM_TOPLEVEL"
  ssh_root "$VM_TOPLEVEL/bin/switch-to-configuration" switch
  [ "$(ssh_vm readlink -f /run/current-system)" = "$VM_TOPLEVEL" ] || die "guest did not activate the tested toplevel"
}

vm_assert_selected_after_boot() {
  local mode="$1" actual
  ssh_vm mkdir -p /home/feltfomo/.cache/skadi-program-files-regression
  actual="$(ssh_vm readlink -f /run/current-system)"
  [ "$actual" = "$VM_TOPLEVEL" ] || die "reboot selected $actual instead of $VM_TOPLEVEL"
  ssh_vm test "$(ssh_vm readlink -f /nix/var/nix/profiles/system)" = "$VM_TOPLEVEL"
  ssh_vm test -e /nix/var/nix/gcroots/program-files-regression/system
  ssh_vm test -e /nix/var/nix/gcroots/program-files-regression/harness
  local evidence_name="case-${mode}-generation-evidence.json"
  [ "$mode" != initial ] || evidence_name="initial-generation-evidence.json"
  jq -n --arg mode "$mode" --arg expected "$VM_TOPLEVEL" --arg actual "$actual" \
    '{mode:$mode,expectedToplevel:$expected,actualToplevel:$actual,exactGenerationSelected:($expected==$actual),systemRootPresent:true,harnessRootPresent:true}' \
    | ssh_vm "cat > /home/feltfomo/.cache/skadi-program-files-regression/$evidence_name"
}

vm_noop_switch() {
  local before after
  before="$(ssh_vm readlink -f /run/current-system)"
  ssh_root nixos-rebuild switch --flake "$VM_ARCHIVE#vm"
  after="$(ssh_vm readlink -f /run/current-system)"
  [ "$before" = "$after" ] || die "no-op switch changed the toplevel: $before -> $after"
  [ "$after" = "$VM_TOPLEVEL" ] || die "no-op switch selected an unexpected toplevel"
}

vm_collect_evidence() {
  local destination="$1"
  mkdir -p "$destination"
  scp_from_vm "$VM_USER@localhost:/home/feltfomo/.cache/skadi-program-files-regression/*.json" "$destination/"
}

vm_equivalence() {
  local khion_matrix="$1" evidence="$2" output="$3" expected khion vm status
  local khion_expected vm_expected vm_khion boot_ids switches persistence generations fixtures all_true
  expected="$(expected_matrix | jq -Sc .)"
  khion="$(normalize_matrix "$khion_matrix" | jq -Sc .)"
  vm="$(normalize_matrix "$evidence/repair-matrix.json" | jq -Sc .)"
  khion_expected=false; vm_expected=false; vm_khion=false
  [ "$khion" = "$expected" ] && khion_expected=true
  [ "$vm" = "$expected" ] && vm_expected=true
  [ "$vm" = "$khion" ] && vm_khion=true
  boot_ids="$(jq -s 'length==3 and all(.[];.bootIdChanged==true and .homePersistence=="persisted")' "$evidence"/case-*-boot-evidence.json)"
  switches="$(jq -s 'length==3 and all(.[];.byteIdenticalToplevel==true)' "$evidence"/case-*-switch-evidence.json)"
  persistence="$(jq -s 'length==3 and all(.[];.negativeControlPassed==true and .persistedSentinelSurvived==true and .persistedSentinelUnchanged==true and .persistedEvidenceSetSurvived==true)' "$evidence"/case-*-persistence-evidence.json)"
  generations="$(jq -s 'length==3 and all(.[];.exactGenerationSelected==true and .systemRootPresent==true and .harnessRootPresent==true)' "$evidence"/case-*-generation-evidence.json)"
  fixtures="$(jq -s 'length==3 and all(.[];.fixtureStateValid==true)' "$evidence"/case-*-boot-evidence.json)"
  all_true=false
  if [ "$khion_expected" = true ] && [ "$vm_expected" = true ] && [ "$vm_khion" = true ] && [ "$boot_ids" = true ] && [ "$switches" = true ] && [ "$persistence" = true ] && [ "$generations" = true ] && [ "$fixtures" = true ]; then all_true=true; fi
  status=finding; [ "$all_true" = true ] && status=pass
  jq -S -n --arg status "$status" --argjson expected "$expected" --argjson khion "$khion" --argjson vm "$vm" \
    --arg khionMatrixPath "$khion_matrix" --arg khionMatrixSha256 "$(content_hash "$khion_matrix")" \
    --arg khionMatrixModifiedAt "$(date --iso-8601=seconds --reference="$khion_matrix")" \
    --arg baselineGeneratedBy "$(jq -r .generatedBy "$PROGRAM_FILES_BASELINE")" \
    --arg baselineSystemToplevel "$(jq -r '.hosts.khion.systemToplevel // null' "$PROGRAM_FILES_BASELINE")" \
    --arg archive "$VM_ARCHIVE" --arg testedToplevel "$VM_TOPLEVEL" --arg regressionApp "$VM_APP" \
    --argjson khionMatchesExpected "$khion_expected" --argjson vmMatchesExpected "$vm_expected" \
    --argjson vmMatchesKhion "$vm_khion" --argjson changedBootIds "$boot_ids" \
    --argjson byteIdenticalSwitches "$switches" --argjson persistenceControls "$persistence" \
    --argjson exactGenerationSelected "$generations" --argjson fixtureStates "$fixtures" \
    '{schemaVersion:1,status:$status,authority:{expectedMatrix:$expected},khionEvidence:{path:$khionMatrixPath,sha256:$khionMatrixSha256,modifiedAt:$khionMatrixModifiedAt,baselineGeneratedBy:$baselineGeneratedBy,baselineSystemToplevel:$baselineSystemToplevel,matrix:$khion},vmEvidence:{matrix:$vm,archive:$archive,testedToplevel:$testedToplevel,regressionApp:$regressionApp},invariants:{khionMatchesExpected:$khionMatchesExpected,vmMatchesExpected:$vmMatchesExpected,vmMatchesKhion:$vmMatchesKhion,changedBootIds:$changedBootIds,byteIdenticalNoOpSwitches:$byteIdenticalSwitches,persistenceAndNegativeControls:$persistenceControls,exactGenerationSelected:$exactGenerationSelected,fixtureStatesValid:$fixtureStates}}' > "$output"
  jq . "$output"
  [ "$status" = pass ] || return 1
}

vm_record_missing_khion() {
  local path="$1" output="$2"
  expected_matrix | jq -S --arg path "$path" '{schemaVersion:1,status:"finding",authority:{expectedMatrix:.},khionEvidence:{path:$path,present:false},finding:"khion repair matrix is missing"}' > "$output"
}

vm_run() {
  local flake="$1" khion_matrix="$2"
  vm_require_run
  mkdir -p "$CACHE"
  local output="$CACHE/vm-khion-equivalence.json"
  if [ ! -f "$khion_matrix" ]; then vm_record_missing_khion "$khion_matrix" "$output"; cat "$output"; return 1; fi
  [ -f "$VM_BASE" ] && [ -f "$VM_BASE_VARS" ] && [ -f "$VM_PROVISION" ] || die "lifecycle base is missing; run vm provision once"
  local run_id run_dir evidence archive_json
  run_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
  run_dir="$VM_CACHE/program-files-run-$run_id"
  evidence="$CACHE/vm-evidence-$run_id"
  mkdir -p "$run_dir" "$evidence"
  VM_OVERLAY="$run_dir/disk.qcow2"
  VM_RUN_VARS="$run_dir/vars.fd"
  VM_SERIAL="$run_dir/serial.log"
  VM_CODE="$OVMF_FD/FV/OVMF_CODE.fd"
  qemu-img create -f qcow2 -F qcow2 -b "$VM_BASE" "$VM_OVERLAY" >/dev/null
  cp "$VM_BASE_VARS" "$VM_RUN_VARS"
  chmod 0600 "$VM_RUN_VARS"
  QEMU_PID=""
  trap 'vm_stop' EXIT
  vm_start
  VM_TEST_FLAKE="$run_dir/source"
  vm_prepare_test_flake "$flake" "$VM_TEST_FLAKE"
  VM_TOPLEVEL="$(nix build --no-link --print-out-paths "${VM_TEST_FLAKE}#nixosConfigurations.vm.config.system.build.toplevel")"
  VM_APP="$(nix build --no-link --print-out-paths "${VM_TEST_FLAKE}#program-files-regression")"
  archive_json="$(nix flake archive --json "$VM_TEST_FLAKE")"
  VM_ARCHIVE="$(jq -r .path <<<"$archive_json")"
  [[ "$VM_ARCHIVE" == /nix/store/* ]] || die "flake archive is not an immutable store path"
  vm_copy_closures
  vm_select_toplevel
  vm_reboot
  vm_assert_selected_after_boot initial
  vm_guest_harness rm-matrix --host vm
  local mode
  for mode in absent dangling drifted; do
    vm_guest_harness case-prepare --host vm --mode "$mode"
    vm_noop_switch
    vm_guest_harness case-switch-assert --host vm --mode "$mode"
    vm_guest_harness case-prepare --host vm --mode "$mode"
    vm_guest_harness_root reboot-prepare --host vm --mode "$mode" --run-id "$run_id"
    vm_reboot
    vm_assert_selected_after_boot "$mode"
    vm_guest_harness_root reboot-assert --host vm --mode "$mode" --run-id "$run_id"
    vm_guest_harness case-boot-assert --host vm --mode "$mode"
  done
  vm_collect_evidence "$evidence"
  cp "$evidence/repair-matrix.json" "$CACHE/vm-repair-matrix.json"
  vm_equivalence "$khion_matrix" "$evidence" "$output"
  log "VM proof passed; disposable overlay retained at $run_dir"
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
  rm-matrix)
    [ "${1:-}" = --host ] && [ -n "${2:-}" ] || die "rm-matrix needs --host"
    require_host "$2"; rm -f "$(matrix_path)";;
  reboot-prepare)
    [ "${1:-}" = --host ] && [ -n "${2:-}" ] && [ "${3:-}" = --mode ] && [ -n "${4:-}" ] && [ "${5:-}" = --run-id ] && [ -n "${6:-}" ] || die "reboot-prepare needs --host, --mode, and --run-id"
    reboot_prepare "$2" "$4" "$6";;
  reboot-assert)
    [ "${1:-}" = --host ] && [ -n "${2:-}" ] && [ "${3:-}" = --mode ] && [ -n "${4:-}" ] && [ "${5:-}" = --run-id ] && [ -n "${6:-}" ] || die "reboot-assert needs --host, --mode, and --run-id"
    reboot_assert "$2" "$4" "$6";;
  vm)
    action="${1:-}"; [ -n "$action" ] || die "vm needs provision or run"; shift
    flake="."; khion_matrix=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --flake) flake="$2"; shift 2;;
        --khion-matrix) khion_matrix="$2"; shift 2;;
        *) die "unknown vm $action argument: $1";;
      esac
    done
    case "$action" in
      provision) vm_provision "$flake";;
      run) [ -n "$khion_matrix" ] || die "vm run needs --khion-matrix"; vm_run "$flake" "$khion_matrix";;
      *) die "unknown vm action: $action";;
    esac
    ;;
  -h|--help|help) usage;;
  *) usage; exit 2;;
esac
