#!/usr/bin/env bash

# runtime evidence stays outside the repo; baselines contain only healthy state.
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
  furnish-symlink --host <khion|vm>
  case-prepare --host khion --mode <absent|dangling|drifted>
  case-switch-assert --host khion --mode <absent|dangling|drifted>
  case-boot-assert --host khion --mode <absent|dangling|drifted>
  vm provision --flake <path>
  vm run --flake <path> --khion-matrix <path>
  vm migrate-gate [--base <path>] --release-toplevel <path> --adopt-toplevel <path>
  reboot-prepare --host vm --mode <absent|dangling|drifted> --run-id <id>
  reboot-assert --host vm --mode <absent|dangling|drifted> --run-id <id>
  fault-prepare --host khion --point <boundary> --coordinator <path>
  fault-assert --host khion --point <boundary> --coordinator <path>
USAGE
}

require_host() {
  local expected="$1" actual
  actual="$(hostnamectl --static 2>/dev/null || hostname)"
  [ "$actual" = "$expected" ] || die "command is for $expected, running on $actual"
}

system_toplevel() { readlink -f /run/current-system; }
content_hash() { sha256sum -- "$1" | awk '{print $1}'; }

ledger_path() {
  # where applied state lives is a property of the evaluated host, not a
  # constant this harness may assume; asking the configuration keeps the two
  # from drifting apart silently.
  local host
  host="$(hostnamectl --static 2>/dev/null || hostname)"
  nix eval --raw ".#nixosConfigurations.${host}.config.lexicon.furnish.ledgerPath"
}

ledger_field() {
  local ledger="$1" destination="$2" field="$3"
  [ -r "$ledger" ] || return 0
  jq -r --arg destination "$destination" --arg field "$field" \
    '[.records[]|select(.destination==$destination)]|first|.[$field] // empty' "$ledger"
}

home_generation() {
  # integrated home manager has used both profile locations across generations.
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
  # a boot result means something different when .config lives on the rolled-back root.
  local mount
  mount="$(findmnt -T "$HOME/.config" -n -o SOURCE,FSROOT,TARGET 2>/dev/null || true)"
  if grep -Eq '(@persist|/persist)' <<<"$mount"; then
    printf 'persisted\n'
  else
    printf 'ephemeral-root\n'
  fi
}

entries() {
  # keep declaration identity separate from volatile store paths in observed state.
  [ -n "${PROGRAM_FILES_MANIFEST:-}" ] || die "PROGRAM_FILES_MANIFEST is missing"
  jq -r '.entries[] | [.declarationIdentity, .destination, .sourceKind, (.sourcePath // "")] | @tsv' "$PROGRAM_FILES_MANIFEST"
}

furnish_target() {
  local host="$1" destination="$2" absolute
  absolute="/home/feltfomo/$destination"
  nix eval --json ".#nixosConfigurations.${host}.config.lexicon.furnish.manifestData"     | jq -r --arg destination "$absolute" '.[] | select(.filesystemIdentity.destination==$destination) | .retainedArtifactTarget'     | head -n1
}

store_object() {
  local path="$1"
  if [[ "$path" == /nix/store/* ]]; then
    printf '/nix/store/%s\n' "$(cut -d/ -f1 <<<"${path#/nix/store/}")"
  fi
}

desired_manifest() {
  # this path evaluates a host but never activates it, so lumi can be compared from khion.
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
        desired_target="$(furnish_target "$host" "$destination")"
      fi
      if [ -z "$desired_target" ]; then
        # ownership may legitimately exclude an entry from this host's desired set.
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
  # desired and realized state are emitted independently so drift never pollutes parity data.
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
      if [ -z "$desired_target" ]; then
        desired_target="$(furnish_target "$host" "$destination")"
      fi
      [ -n "$desired_target" ] && [ -e "$desired_target" ] || die "evaluation did not produce a live source for $destination"
    fi
    desired_hash="$(content_hash "$desired_target")"

    # unknown shapes default to foreign; only proved representations may be repaired.
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
    # keep scanning evidence useful while refusing to bless any unhealthy corpus.
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
  # destination, failure class, and raw target must all survive to count as non-repair.
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
  # equality isn't ownership proof; a foreign entry is never test setup to overwrite.
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
  # failure evidence stays in CACHE; assembled output contains only healthy parity data.
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

# fault injection. the points are named after the durability boundaries the
# coordinator actually has, and the crash is a real process death at that point
# rather than an error return, so recovery is exercised the way a power loss
# would exercise it. evidence lands beside the repair matrix in its own file;
# the matrix schema is not touched.
FAULT_POINTS="pre-pending pending-committed stage-written stage-synced published published-synced verified exchange-published"

fault_root() { printf '%s/fault\n' "$CACHE"; }
fault_recovery_path() { printf '%s/furnish-fault-recovery.json\n' "$CACHE"; }

fault_known_point() {
  local point="$1" candidate
  for candidate in $FAULT_POINTS; do
    [ "$candidate" = "$point" ] && return 0
  done
  return 1
}

fault_manifest_json() {
  local destination="$1" root="$2" source="$3" representation="$4" executor="$5" strategy="$6"
  jq -n --arg destination "$destination" --arg root "$root" --arg source "$source" \
    --arg representation "$representation" --arg executor "$executor" --arg strategy "$strategy" '{
    schemaVersion:1,
    diagnosticContract:{
      schemaVersion:1,
      codes:{
        invalidManifest:"runtime/invalid-manifest",
        unsupportedExecutor:"runtime/unsupported-executor",
        invalidDestination:"runtime/invalid-destination",
        parentTraversal:"runtime/parent-traversal",
        conflictingDestination:"runtime/conflicting-destination",
        executorFailed:"runtime/executor-failed",
        stagingVerification:"runtime/staging-verification",
        publishRace:"runtime/publish-race",
        finalVerification:"runtime/final-verification",
        ledgerUnreadable:"runtime/ledger-unreadable",
        ledgerInvalid:"runtime/ledger-invalid",
        ledgerWriteFailed:"runtime/ledger-write-failed",
        repairVerification:"runtime/repair-verification",
        unresolvableDesiredTarget:"runtime/unresolvable-desired-target",
        contentVerification:"runtime/content-verification",
        transitionRefused:"runtime/transition-refused",
        unresolvedRetirement:"runtime/unresolved-retirement",
        pendingRecovery:"runtime/pending-recovery"
      }
    },
    entries:[{
      schemaVersion:1,
      filesystemIdentity:{namespace:"fault",destination:$destination,canonical:("fault:"+$destination)},
      authority:{scope:"system",identity:"fault/system"},
      managedRoot:$root,
      representation:$representation,
      retainedArtifactTarget:$source,
      executor:{identity:$executor,protocolVersion:1},
      cleanupStrategy:$strategy,
      selfHealStrategy:$strategy,
      provenance:{declaration:"fault-injection",source:"scripts/program-files-regression.sh"}
    }]
  }'
}

# scratch only, and under the cache. no host declaration is added and nothing
# outside $CACHE is written.
fault_scratch() {
  local point="$1" scratch
  scratch="$(fault_root)/$point"
  rm -rf "$scratch"
  mkdir -p "$scratch/managed" "$scratch/state" "$scratch/lock"
  printf 'furnish writable payload\n' > "$scratch/source"
  printf '%s\n' "$scratch"
}

fault_run() {
  local coordinator="$1" scratch="$2" manifest="$3" point="$4"
  local setpriv
  setpriv="$(command -v setpriv)" || die "setpriv is required"
  if [ -n "$point" ]; then
    env FURNISH_FAULT_POINT="$point" "$coordinator" reconcile \
      --manifest "$manifest" --lock-name fault.lock --setpriv "$setpriv" \
      --state-dir "$scratch/state" --lock-dir "$scratch/lock"
  else
    "$coordinator" reconcile \
      --manifest "$manifest" --lock-name fault.lock --setpriv "$setpriv" \
      --state-dir "$scratch/state" --lock-dir "$scratch/lock"
  fi
}

fault_prepare() {
  local host="$1" point="$2" coordinator="$3" scratch manifest status
  require_host "$host"
  fault_known_point "$point" || die "unknown fault point: $point"
  [ -x "$coordinator" ] || die "fault coordinator is not executable: $coordinator"
  scratch="$(fault_scratch "$point")"
  manifest="$scratch/manifest.json"

  if [ "$point" = exchange-published ]; then
    # a crash between the exchange and the ledger advancing only happens during a
    # transfer, so an owned symlink has to be established first and then asked to
    # become writable.
    fault_manifest_json "$scratch/managed/value" "$scratch/managed" "$scratch/source" \
      symlink furnish/native-symlink exact-symlink-target > "$manifest"
    fault_run "$coordinator" "$scratch" "$manifest" "" || die "could not establish the owned symlink"
  fi

  fault_manifest_json "$scratch/managed/value" "$scratch/managed" "$scratch/source" \
    writable furnish/native-writable exact-source-content > "$manifest"

  # packaged as a shell application the script runs under errexit; invoked
  # directly with bash it does not. the status is captured explicitly rather
  # than toggled around because that form is correct under both, and a stray
  # set -e or set +e here would change how every other subcommand behaves.
  status=0
  fault_run "$coordinator" "$scratch" "$manifest" "$point" || status=$?
  # abort() is SIGABRT, so a shell reports 134. anything else means the process
  # returned instead of dying, and the point would not be proving what it claims.
  [ "$status" -eq 134 ] || die "fault point $point did not die: exit $status"
  log "fault point $point crashed as expected"
}

fault_assert() {
  local host="$1" point="$2" coordinator="$3" scratch manifest status
  local destination expected actual state baseline recovered entry
  require_host "$host"
  fault_known_point "$point" || die "unknown fault point: $point"
  scratch="$(fault_root)/$point"
  manifest="$scratch/manifest.json"
  [ -f "$manifest" ] || die "no prepared fault scratch for $point"
  destination="$scratch/managed/value"

  status=0
  fault_run "$coordinator" "$scratch" "$manifest" "" || status=$?
  [ "$status" -eq 0 ] || die "recovery run failed at $point: exit $status"

  expected="$(content_hash "$scratch/source")"
  [ -f "$destination" ] || die "recovery at $point left no destination"
  [ -L "$destination" ] && die "recovery at $point left a symlink, not a writable file"
  actual="$(content_hash "$destination")"
  [ "$actual" = "$expected" ] || die "recovery at $point did not converge byte-exactly"

  entry="$(jq -r --arg key "fault:$destination" '.records[$key] // empty' "$scratch/state/applied-state.json")"
  [ -n "$entry" ] || die "recovery at $point recorded no ownership"
  state="$(printf '%s' "$entry" | jq -r '.state')"
  # the ledger serializes camelCase, so the key here must match the file on
  # disk rather than the rust field name.
  baseline="$(printf '%s' "$entry" | jq -r '.baselineHash // empty')"
  [ "$state" = owned ] || die "recovery at $point left state $state"
  [ "$baseline" = "$expected" ] || die "recovery at $point left a stale baseline"

  # no partial write is ever claimed as complete. ownership is asserted here
  # only because the bytes were re-read and re-hashed after the fact.
  recovered="$(jq -n --arg point "$point" --arg hash "$actual" --arg baseline "$baseline" \
    '{point:$point,status:"pass",converged:true,contentHash:$hash,baselineHash:$baseline,ownershipState:"owned"}')"
  if [ -f "$(fault_recovery_path)" ]; then
    jq --argjson entry "$recovered" '.points |= (map(select(.point != $entry.point)) + [$entry])' \
      "$(fault_recovery_path)" > "$(fault_recovery_path).tmp"
  else
    jq -n --argjson entry "$recovered" '{schemaVersion:1,points:[$entry]}' > "$(fault_recovery_path).tmp"
  fi
  mv "$(fault_recovery_path).tmp" "$(fault_recovery_path)"
  log "fault point $point recovered to exact known state"
}

ensure_matrix() {
  # null cells make an interrupted matrix obvious instead of looking like a pass.
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
  local mode="$1" file="$2" raw resolved hash ledger ledger_schema applied
  [ -L "$KITTY_PATH" ] || die "$KITTY_PATH is not a healthy owned symlink"
  raw="$(readlink -- "$KITTY_PATH")"
  resolved="$(readlink -f -- "$KITTY_PATH")"
  [ -e "$resolved" ] || die "$KITTY_PATH is already dangling"
  hash="$(content_hash "$KITTY_PATH")"
  # the before side of the ledger comparison is captured here so both halves of
  # the reboot assertion come from one place rather than being reconstructed
  # after the wipe from something that may itself have changed.
  ledger="$(ledger_path)"
  ledger_schema="$(jq -r .schemaVersion "$ledger" 2>/dev/null || true)"
  applied="$(ledger_field "$ledger" "$KITTY_PATH" appliedArtifactTarget)"
  jq -n --arg mode "$mode" --arg path "$KITTY_PATH" --arg rawTarget "$raw" --arg resolvedTarget "$resolved" --arg contentSha256 "$hash" --arg systemToplevel "$(system_toplevel)" --arg bootId "$(cat /proc/sys/kernel/random/boot_id)" --arg homePersistence "$(home_persistence)" --arg ledgerPath "$ledger" --arg ledgerSchemaVersion "$ledger_schema" --arg ledgerAppliedTarget "$applied" '{mode:$mode,path:$path,rawTarget:$rawTarget,resolvedTarget:$resolvedTarget,contentSha256:$contentSha256,systemToplevel:$systemToplevel,bootId:$bootId,homePersistence:$homePersistence,ledgerPath:$ledgerPath,ledgerSchemaVersion:(if $ledgerSchemaVersion=="" then null else ($ledgerSchemaVersion|tonumber) end),ledgerAppliedTarget:(if $ledgerAppliedTarget=="" then null else $ledgerAppliedTarget end)}' > "$file"
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
  # the three states expose the backend's missing-versus-invalid-presence behavior.
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
      # delete a real store object first; a made-up path wouldn't prove GC-shaped drift.
      fixture="$CACHE/dangling-fixture"
      printf 'removed kitty target fixture\n' > "$fixture"
      manufactured="$(nix store add-file "$fixture")"
      nix-store --delete "$manufactured" >/dev/null
      [ ! -e "$manufactured" ] || die "could not remove dangling fixture target"
      ln -sfn -- "$manufactured" "$KITTY_PATH"
      ;;
    drifted)
      # keep this object live so the drifted case can't collapse into the dangling case.
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
  # repair requires both the expected target identity and its exact bytes.
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
  # a changed boot ID prevents a second shell invocation from masquerading as reboot proof.
  local host="$1" mode="$2" state before after outcome manufactured fixture_valid expected_hash
  local ledger ledger_schema applied_before applied_after applied_by record_boot_id ledger_boot_id_changed
  require_host "$host"
  state="$CACHE/case-${mode}-state.json"
  [ -f "$state" ] || die "case state is missing for $mode"
  before="$(jq -r .bootId "$state")"
  after="$(cat /proc/sys/kernel/random/boot_id)"
  [ "$before" != "$after" ] || die "boot ID did not change"
  outcome="$(case_outcome "$state")"

  # the ledger is the whole claim here. /persist outlives the initrd snapshot that
  # rolls @ back to @blank, and without the record furnish can prove ownership of
  # nothing once the root is gone. record identity is asserted, never file bytes,
  # because the boot reconcile legitimately rewrites this file and a byte-identical
  # ledger across a boot would mean the boot service never ran.
  ledger="$(jq -r .ledgerPath "$state")"
  [ -f "$ledger" ] || die "applied-state ledger did not survive the reboot: $ledger"
  ledger_schema="$(jq -r .schemaVersion "$ledger")"
  [ "$ledger_schema" = "$(jq -r .ledgerSchemaVersion "$state")" ] || die "applied-state schema changed across the reboot"
  applied_before="$(jq -r .ledgerAppliedTarget "$state")"
  applied_after="$(ledger_field "$ledger" "$KITTY_PATH" appliedArtifactTarget)"
  applied_by="$(ledger_field "$ledger" "$KITTY_PATH" appliedBy)"
  [ -n "$applied_after" ] || die "applied state lost its record for $KITTY_PATH"
  [ -n "$applied_by" ] || die "applied state does not say which branch published $KITTY_PATH"
  if [ "$applied_before" != null ]; then
    [ "$applied_after" = "$applied_before" ] || die "recorded target changed across the reboot: $applied_before -> $applied_after"
  fi
  record_boot_id="$(ledger_field "$ledger" "$KITTY_PATH" bootId)"
  ledger_boot_id_changed=false
  if [ -n "$record_boot_id" ] && [ "$record_boot_id" != "$before" ]; then ledger_boot_id_changed=true; fi
  # only a reconcile that published something rewrites the record, so a refused
  # mode legitimately still carries the previous boot's diagnostic ID.
  if [ "$outcome" = repaired ]; then
    [ "$ledger_boot_id_changed" = true ] || die "ledger boot ID did not advance despite a repaired outcome"
  fi

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
      --arg ledgerPath "$ledger" --arg ledgerAppliedTarget "$applied_after" --arg ledgerAppliedBy "$applied_by" \
      --argjson ledgerBootIdChanged "$ledger_boot_id_changed" \
      '{mode:$mode,bootIdBefore:$bootIdBefore,bootIdAfter:$bootIdAfter,bootIdChanged:($bootIdBefore!=$bootIdAfter),outcome:$outcome,homePersistence:$homePersistence,manufacturedTarget:$manufacturedTarget,fixtureStateValid:$fixtureStateValid,ledgerPath:$ledgerPath,ledgerAppliedTarget:$ledgerAppliedTarget,ledgerAppliedBy:$ledgerAppliedBy,ledgerBootIdChanged:$ledgerBootIdChanged,ledgerSurvived:true,ledgerRecordStable:true,healthyStateRestored:true}' \
      > "$CACHE/case-${mode}-boot-evidence.json"
  else
    jq -n --arg mode "$mode" --arg bootIdBefore "$before" --arg bootIdAfter "$after" --arg outcome "$outcome" --arg homePersistence "$(jq -r .homePersistence "$state")" --arg ledgerPath "$ledger" --arg ledgerAppliedTarget "$applied_after" --arg ledgerAppliedBy "$applied_by" --argjson ledgerBootIdChanged "$ledger_boot_id_changed" '{mode:$mode,bootIdBefore:$bootIdBefore,bootIdAfter:$bootIdAfter,bootIdChanged:($bootIdBefore!=$bootIdAfter),outcome:$outcome,homePersistence:$homePersistence,ledgerPath:$ledgerPath,ledgerAppliedTarget:$ledgerAppliedTarget,ledgerAppliedBy:$ledgerAppliedBy,ledgerBootIdChanged:$ledgerBootIdChanged,ledgerSurvived:true,ledgerRecordStable:true,healthyStateRestored:true}' > "$CACHE/case-${mode}-boot-evidence.json"
  fi
  log "$mode reboot outcome: $outcome; healthy state verified"
}

roots_check() {
  # a live target isn't retention evidence until an active root reaches it.
  require_host khion
  [ -L "$KITTY_PATH" ] || die "kitty.conf is not a symlink"
  local target roots
  target="$(readlink -f -- "$KITTY_PATH")"
  roots="$(nix-store -q --roots "$target" 2>/dev/null || true)"
  [ -n "$roots" ] || die "no GC root reaches $target"
  printf '%s\n' "$roots" > "$CACHE/khion-kitty-roots.txt"
  log "active roots retain $target"
}

furnish_symlink() {
  local host="$1" manifest target raw
  require_host "$host"
  manifest="$(nix eval --json ".#nixosConfigurations.${host}.config.lexicon.furnish.manifestData")"
  [ "$(jq '[.[]|select(.filesystemIdentity.destination=="/home/feltfomo/.config/kitty/kitty.conf")]|length' <<<"$manifest")" -eq 1 ]     || die "furnish manifest does not contain exactly one kitty.conf entry"
  target="$(jq -r '.[]|select(.filesystemIdentity.destination=="/home/feltfomo/.config/kitty/kitty.conf")|.retainedArtifactTarget' <<<"$manifest")"
  [ -L "$KITTY_PATH" ] || die "kitty.conf is not a symlink"
  raw="$(readlink -- "$KITTY_PATH")"
  [ "$raw" = "$target" ] || die "kitty.conf does not point at the exact retained target"
  [ -e "$target" ] || die "retained kitty target is missing"
  jq -n --arg host "$host" --arg destination "$KITTY_PATH" --arg target "$target" --arg rawTarget "$raw"     '{schemaVersion:1,status:"pass",host:$host,destination:$destination,representation:"symlink",exactTarget:($target==$rawTarget),targetExists:true,statelessSemantics:true}'     > "$CACHE/furnish-symlink-${host}.json"
  log "furnish native symlink target is exact for $host"
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
  # guest subcommands such as furnish-symlink evaluate .#vm. run them from the
  # exact prepared archive instead of the SSH user's flake-less home directory.
  ssh_vm env --chdir="$VM_ARCHIVE" PWD="$VM_ARCHIVE" \
    HOME=/home/feltfomo SKADI_PROGRAM_FILES_CACHE=/home/feltfomo/.cache/skadi-program-files-regression \
    "$VM_APP/bin/program-files-regression" "$@"
}

vm_guest_harness_root() {
  ssh_root env --chdir="$VM_ARCHIVE" PWD="$VM_ARCHIVE" \
    HOME=/home/feltfomo SKADI_PROGRAM_FILES_CACHE=/home/feltfomo/.cache/skadi-program-files-regression \
    "$VM_APP/bin/program-files-regression" "$@"
}

vm_real_sops_inventory() {
  local source="$1"
  (
    cd "$source"
    find .sops.yaml secrets -type f -print0 | sort -z | xargs -0 -r sha256sum
  )
}

vm_prepare_identity_fixture() (
  # the switch target must use the identity already installed in the golden.
  # reading only its public half keeps the private key inside the guest.
  umask 077
  local destination="$1" public_key recipient work plaintext encrypted fixture
  local before_inventory after_inventory leaked actual_keys expected_keys
  local fixed_password fixed_token
  public_key="$(ssh_vm cat /etc/ssh/ssh_host_ed25519_key.pub)"
  [[ "$public_key" == ssh-ed25519\ * ]] || die "golden VM returned a malformed ed25519 host public key"
  recipient="$(printf '%s\n' "$public_key" | ssh-to-age)"
  [[ "$recipient" == age1* ]] || die "could not derive the golden VM age recipient"

  work="$(mktemp -d)"
  trap 'rm -rf "$work"' EXIT
  plaintext="$work/secrets.plain.yaml"
  encrypted="$work/secrets.yaml"
  fixture="$destination/modules/hosts/_vm/secrets.yaml"
  before_inventory="$work/real-sops-before.sha256"
  after_inventory="$work/real-sops-after.sha256"
  vm_real_sops_inventory "$destination" > "$before_inventory"

  fixed_password="\$6\$skadivmtest\$tp5BUeNDHy1miR21O7X2QXROL/yxzqnT9XeKJ4UKI.PpyYdkise0/iV58ErEoKs5SuKbvW/xy93Mzu3lQ2Fgf0"
  fixed_token="NOTION_TOKEN=REPLACE_ME"
  printf 'feltfomo-password: "%s"\nnotion-token: "%s"\n' \
    "$fixed_password" "$fixed_token" > "$plaintext"
  [ "$(wc -l < "$plaintext")" -eq 2 ] || die "VM fixture plaintext must contain exactly two secrets"
  grep -Fqx -- "feltfomo-password: \"$fixed_password\"" "$plaintext" \
    || die "VM fixture password is not the fixed fake value"
  grep -Fqx -- "notion-token: \"$fixed_token\"" "$plaintext" \
    || die "VM fixture token is not the fixed fake value"

  (
    cd "$work"
    sops --encrypt --age "$recipient" --input-type yaml --output-type yaml "$plaintext"
  ) > "$encrypted"
  grep -Fq -- "$fixed_password" "$encrypted" && die "VM fixture ciphertext contains password plaintext"
  grep -Fq -- "$fixed_token" "$encrypted" && die "VM fixture ciphertext contains token plaintext"
  actual_keys="$(awk -F: '/^[A-Za-z0-9_-]+:/ {print $1}' "$encrypted" | sort)"
  expected_keys="$(printf '%s\n' feltfomo-password notion-token sops | sort)"
  [ "$actual_keys" = "$expected_keys" ] || die "encrypted VM fixture does not contain exactly the two fake secret keys"

  install -D -m 0644 "$encrypted" "$fixture"
  vm_real_sops_inventory "$destination" > "$after_inventory"
  cmp -s "$before_inventory" "$after_inventory" \
    || die "real .sops.yaml or secrets/ material changed while preparing the VM fixture"
  leaked="$(find "$destination" -type f \( -name ssh_host_ed25519_key -o -name ssh_host_ed25519_key.pub \) -print -quit)"
  [ -z "$leaked" ] || die "VM identity key leaked into prepared source: $leaked"
  log "prepared disposable VM secrets fixture for the installed golden identity"
)

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

  vm_prepare_identity_fixture "$destination"
  git -C "$destination" init -q
  git -C "$destination" add -A
  git -C "$destination" ls-files --error-unmatch modules/hosts/_vm/secrets.yaml >/dev/null \
    || die "generated VM fixture was not staged in the disposable source"
  git -C "$destination" -c user.name=program-files-regression \
    -c user.email=program-files-regression@invalid commit -qm "disposable VM test source"
}

vm_build_release_toplevel() {
  local flake="$1" flake_ref release_expr probe toplevel
  flake_ref="$(printf '%s' "git+file://$flake" | jq -Rs .)"
  release_expr="let
    flake = builtins.getFlake $flake_ref;
  in
    flake.nixosConfigurations.vm.extendModules {
      modules = [
        ({ lib, ... }: {
          lexicon.furnish.declarations = lib.mkForce [ ];
        })
      ];
    }"
  probe="$(nix eval --impure --json --expr "let release = ($release_expr); in {
    runtimeModulePresent = release.options.lexicon.furnish ? declarations;
    declarations = release.config.lexicon.furnish.declarations;
    manifestData = release.config.lexicon.furnish.manifestData;
    manifestPath = release.config.lexicon.furnish.manifestPath;
    hasActivation = release.config.system.activationScripts ? furnish;
    hasBootService = release.config.systemd.services ? furnish;
  }")"
  # enabled with nothing declared is a running state, not an inert one. the empty
  # reconciliation is what retires entries a later generation stops declaring, so
  # it needs a manifest, an activation and a unit even at zero entries, and
  # furnish running there with an empty ledger and pruning nothing is a stronger
  # non-interference proof than furnish not running at all.
  jq -e '.runtimeModulePresent == true and .declarations == [] and .manifestData == [] and .manifestPath != null and .hasActivation == true and .hasBootService == true' <<<"$probe" >/dev/null \
    || die "release generation did not keep furnish enabled and running with an empty desired set"
  printf '%s\n' "$probe" | jq -S . > "$CACHE/release-generation-probe.json"
  toplevel="$(nix build --impure --no-link --print-out-paths --expr "($release_expr).config.system.build.toplevel")"
  [[ "$toplevel" == /nix/store/* ]] && [ -e "$toplevel" ] \
    || die "release generation did not produce a live system toplevel: $toplevel"
  printf '%s\n' "$toplevel"
}

vm_record_integrated_migration() {
  ssh_vm mkdir -p /home/feltfomo/.cache/skadi-program-files-regression
  jq -n --arg base "$VM_BASE" --arg release "$VM_RELEASE_TOPLEVEL" --arg adopt "$VM_TOPLEVEL" \
    '{schemaVersion:1,status:"pass",base:$base,releaseToplevel:$release,adoptToplevel:$adopt,selfSmokePassed:true,releaseEnabledEmpty:true,releaseHandoff:true,adoptTakeover:true,adoptSelectedForBoot:true}' \
    | ssh_vm 'cat > /home/feltfomo/.cache/skadi-program-files-regression/furnish-migrate-gate.json'
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

vm_copy_toplevel() {
  # the two-generation migration check needs only a system toplevel, with no app,
  # archive, or in-guest harness, so it roots exactly one path.
  local toplevel="$1" ssh_opts
  ssh_opts="-i $VM_KEY -p $VM_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
  env NIX_SSHOPTS="$ssh_opts" nix copy --no-check-sigs --to "ssh-ng://$VM_USER@localhost" "$toplevel"
  ssh_root mkdir -p /nix/var/nix/gcroots/program-files-regression
  ssh_root ln -sfn "$toplevel" /nix/var/nix/gcroots/program-files-regression/migrate-system
}

vm_select_toplevel() {
  # migrate_apply already activated and verified the adopt generation. publish it
  # as the boot default without replaying activation a third time.
  ssh_root nix-env -p /nix/var/nix/profiles/system --set "$VM_TOPLEVEL"
  ssh_root "$VM_TOPLEVEL/bin/switch-to-configuration" boot
  [ "$(ssh_vm readlink -f /run/current-system)" = "$VM_TOPLEVEL" ] \
    || die "adopt generation stopped being active before boot selection"
  [ "$(ssh_vm readlink -f /nix/var/nix/profiles/system)" = "$VM_TOPLEVEL" ] \
    || die "adopt generation was not selected as the boot profile"
  log "adopt generation selected as the boot default"
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
  local mode="$1" before after rc switch_log
  before="$(ssh_vm readlink -f /run/current-system)"
  switch_log="$CACHE/case-${mode}-switch-command.log"
  if ssh_root nixos-rebuild switch --flake "$VM_ARCHIVE#vm" 2>&1 | tee "$switch_log"; then
    rc=0
  else
    rc=${PIPESTATUS[0]}
  fi
  after="$(ssh_vm readlink -f /run/current-system)"
  [ "$before" = "$after" ] || die "no-op switch changed the toplevel: $before -> $after"
  [ "$after" = "$VM_TOPLEVEL" ] || die "no-op switch selected an unexpected toplevel"
  case "$mode" in
    absent)
      [ "$rc" -eq 0 ] || die "absent no-op switch failed (rc=$rc)"
      ;;
    dangling|drifted)
      [ "$rc" -ne 0 ] || die "$mode no-op switch unexpectedly accepted the conflicting destination"
      grep -F '"code":"runtime/conflicting-destination"' "$switch_log" >/dev/null \
        || die "$mode no-op switch failed without the conflicting-destination diagnostic"
      ;;
    *) die "unknown no-op switch mode: $mode";;
  esac
}

vm_gc_survival() {
  local target_before target_after roots_before roots_after
  target_before="$(ssh_vm readlink -f /home/feltfomo/.config/kitty/kitty.conf)"
  [ -n "$target_before" ] || die "VM kitty target is missing before GC"
  roots_before="$(ssh_root nix-store -q --roots "$target_before")"
  [ -n "$roots_before" ] || die "VM kitty target has no root before GC"
  ssh_root nix-collect-garbage -d >/dev/null
  ssh_vm test -L /home/feltfomo/.config/kitty/kitty.conf
  target_after="$(ssh_vm readlink -f /home/feltfomo/.config/kitty/kitty.conf)"
  [ "$target_after" = "$target_before" ] || die "VM kitty target changed across GC"
  ssh_vm test -e "$target_after"
  roots_after="$(ssh_root nix-store -q --roots "$target_after")"
  [ -n "$roots_after" ] || die "VM kitty target lost its root after GC"
  jq -n --arg targetBefore "$target_before" --arg targetAfter "$target_after"     --arg rootsBefore "$roots_before" --arg rootsAfter "$roots_after"     '{schemaVersion:1,status:"pass",targetBefore:$targetBefore,targetAfter:$targetAfter,exactTargetSurvived:($targetBefore==$targetAfter),targetExistsAfterGc:true,rootPresentBefore:true,rootPresentAfter:true,positiveGcRun:true}'     | ssh_vm 'cat > /home/feltfomo/.cache/skadi-program-files-regression/furnish-gc-survival.json'
}

vm_build_variant_toplevel() {
  # the only honest second target is one a real declaration produced. perturb the
  # declared kitty source the way a user edit would and evaluate the same module,
  # rather than hand-writing a manifest entry the module never emitted.
  local source="$1" destination="$2" config toplevel
  [ ! -e "$destination" ] || die "variant source already exists: $destination"
  cp -a "$source" "$destination"
  config="$destination/configs/kitty/kitty.conf"
  [ -f "$config" ] || die "variant source is missing the declared kitty config: $config"
  printf '\n# two-generation gc repair fixture\n' >> "$config"
  git -C "$destination" -c user.name=program-files-regression \
    -c user.email=program-files-regression@invalid commit -qam "gc repair variant source"
  toplevel="$(nix build --no-link --print-out-paths "${destination}#nixosConfigurations.vm.config.system.build.toplevel")"
  { [[ "$toplevel" == /nix/store/* ]] && [ -e "$toplevel" ]; } \
    || die "variant generation did not produce a live system toplevel: $toplevel"
  printf '%s\n' "$toplevel"
}

vm_ledger_field() {
  ssh_vm cat "$1" | jq -r --arg destination "$2" --arg field "$3" \
    '[.records[]|select(.destination==$destination)]|first|.[$field] // empty'
}

vm_build_disabled_toplevel() {
  # masking writes into /etc, which this guest wipes on every boot, so a masked
  # unit would dissolve at exactly the moment it has to hold. declaring furnish
  # off is inert by construction and nothing in the rollback can undo it.
  local source="$1" flake_ref disabled_expr probe toplevel
  flake_ref="$(printf '%s' "git+file://$source" | jq -Rs .)"
  disabled_expr="let
    flake = builtins.getFlake $flake_ref;
  in
    flake.nixosConfigurations.vm.extendModules {
      modules = [
        ({ lib, ... }: {
          lexicon.furnish.enable = lib.mkForce false;
        })
      ];
    }"
  probe="$(nix eval --impure --json --expr "let disabled = ($disabled_expr); in {
    enabled = disabled.config.lexicon.furnish.enable;
    hasActivation = disabled.config.system.activationScripts ? furnish;
    hasBootService = disabled.config.systemd.services ? furnish;
  }")"
  jq -e '.enabled == false and .hasActivation == false and .hasBootService == false' <<<"$probe" >/dev/null \
    || die "disabled generation still carries a furnish activation script or unit"
  printf '%s\n' "$probe" | jq -S . > "$CACHE/disabled-generation-probe.json"
  toplevel="$(nix build --impure --no-link --print-out-paths --expr "($disabled_expr).config.system.build.toplevel")"
  { [[ "$toplevel" == /nix/store/* ]] && [ -e "$toplevel" ]; } \
    || die "disabled generation did not produce a live system toplevel: $toplevel"
  printf '%s\n' "$toplevel"
}

vm_gc_repair_survival() {
  # nothing here passes --ignore-liveness, because the artifact has to become
  # unreachable on its own or the reap proves nothing. runs last because it burns
  # a generation and reboots three times.
  local source="$1" destination="$2" guest_path=/home/feltfomo/.config/kitty/kitty.conf
  local ledger variant variant_target base_target disabled inert_load_state
  local recorded_before recorded_updated recorded_after branch_updated branch_after
  local linked_before linked_updated linked_intermediate linked_after
  local update_result repair_result
  ledger="$(nix eval --raw "${source}#nixosConfigurations.vm.config.lexicon.furnish.ledgerPath")"
  linked_before="$(ssh_vm readlink -- "$guest_path")"
  recorded_before="$(vm_ledger_field "$ledger" "$guest_path" appliedArtifactTarget)"
  [ -n "$recorded_before" ] || die "applied state holds no record for $guest_path before the rollback"
  [ "$recorded_before" = "$linked_before" ] || die "applied state does not match the published link before the rollback"
  base_target="$recorded_before"

  variant="$(vm_build_variant_toplevel "$source" "$destination")"
  [ "$variant" != "$VM_TOPLEVEL" ] || die "variant generation is identical to the tested generation"
  variant_target="$(nix eval --json "${destination}#nixosConfigurations.vm.config.lexicon.furnish.manifestData" \
    | jq -r --arg destination "$guest_path" '.[]|select(.filesystemIdentity.destination==$destination)|.retainedArtifactTarget')"
  [ -n "$variant_target" ] && [ "$variant_target" != "$base_target" ] \
    || die "variant generation did not produce a different retained target"
  vm_copy_toplevel "$variant"

  # boot selection rather than activation, so the reconcile happens once and the
  # decision belongs to the boot service. the recorded target is still live here,
  # so this is the update branch.
  ssh_root nix-env -p /nix/var/nix/profiles/system --set "$variant"
  ssh_root "$variant/bin/switch-to-configuration" boot
  ssh_root ln -sfn "$variant" /nix/var/nix/gcroots/program-files-regression/system
  vm_reboot
  [ "$(ssh_vm readlink -f /run/current-system)" = "$variant" ] || die "guest did not boot the variant generation"
  update_result="$(ssh_root systemctl show -p Result --value furnish.service)"
  [ "$update_result" = success ] || die "furnish did not finish cleanly on the update boot (Result=$update_result)"
  linked_updated="$(ssh_vm readlink -- "$guest_path")"
  [ "$linked_updated" = "$variant_target" ] || die "owned update did not republish to the variant target: $linked_updated"
  ssh_vm test -e "$linked_updated" || die "updated link does not resolve"
  recorded_updated="$(vm_ledger_field "$ledger" "$guest_path" appliedArtifactTarget)"
  [ "$recorded_updated" = "$variant_target" ] || die "applied state did not advance on the owned update"
  branch_updated="$(vm_ledger_field "$ledger" "$guest_path" appliedBy)"
  [ "$branch_updated" = update ] || die "applied state recorded $branch_updated where the update branch ran"

  # the rollback boot runs a generation that declares furnish off, so there is no
  # unit and no activation for the collection below to race. the precondition is
  # made of configuration rather than of a runtime poke at the init system, which
  # is the only kind that survives this guest wiping its root.
  disabled="$(vm_build_disabled_toplevel "$source")"
  { [ "$disabled" != "$VM_TOPLEVEL" ] && [ "$disabled" != "$variant" ]; } \
    || die "disabled generation is identical to a generation already under test"
  vm_copy_toplevel "$disabled"
  ssh_root nix-env -p /nix/var/nix/profiles/system --set "$disabled"
  ssh_root "$disabled/bin/switch-to-configuration" boot
  # the variant has to stop being rooted or the collection cannot reach its
  # artifact, and a reap that never could have happened proves nothing. the tested
  # generation keeps its root, and its target is where the repair has to land.
  ssh_root ln -sfn "$VM_TOPLEVEL" /nix/var/nix/gcroots/program-files-regression/system
  vm_reboot
  [ "$(ssh_vm readlink -f /run/current-system)" = "$disabled" ] || die "guest did not boot the disabled generation"
  inert_load_state="$(ssh_root systemctl show -p LoadState --value furnish.service)"
  [ "$inert_load_state" = not-found ] || die "disabled generation still has a furnish unit (LoadState=$inert_load_state)"
  linked_intermediate="$(ssh_vm readlink -- "$guest_path")"
  [ "$linked_intermediate" = "$variant_target" ] || die "inert boot reconciled anyway: $linked_intermediate"

  # the variant is an unrooted older profile generation by now, so its artifact
  # becomes unreachable without anything being forced.
  ssh_root nix-collect-garbage -d >/dev/null
  if ssh_vm test -e "$variant_target"; then die "ordinary garbage collection did not reap the rolled-back target"; fi
  ssh_vm test -e "$base_target" || die "the rooted tested generation lost its target to the collection"
  [ "$(ssh_vm readlink -- "$guest_path")" = "$variant_target" ] || die "link moved while furnish was inert"

  # a dangling link whose target still matches the record is the repair branch.
  ssh_root nix-env -p /nix/var/nix/profiles/system --set "$VM_TOPLEVEL"
  ssh_root "$VM_TOPLEVEL/bin/switch-to-configuration" boot
  vm_reboot
  [ "$(ssh_vm readlink -f /run/current-system)" = "$VM_TOPLEVEL" ] || die "guest did not return to the tested generation"
  repair_result="$(ssh_root systemctl show -p Result --value furnish.service)"
  [ "$repair_result" = success ] || die "furnish did not finish cleanly after the reap (Result=$repair_result)"
  linked_after="$(ssh_vm readlink -- "$guest_path")"
  [ "$linked_after" = "$base_target" ] || die "link was not repaired to the earlier target: $linked_after"
  ssh_vm test -e "$linked_after" || die "repaired link does not resolve"
  recorded_after="$(vm_ledger_field "$ledger" "$guest_path" appliedArtifactTarget)"
  [ "$recorded_after" = "$base_target" ] || die "applied state did not advance to the repaired target"
  branch_after="$(vm_ledger_field "$ledger" "$guest_path" appliedBy)"
  [ "$branch_after" = repair ] || die "applied state recorded $branch_after where the repair branch ran"

  jq -n --arg baseTarget "$base_target" --arg variantTarget "$variant_target" \
    --arg linkedUpdated "$linked_updated" --arg linkedAfter "$linked_after" \
    --arg recordedUpdated "$recorded_updated" --arg recordedAfter "$recorded_after" \
    --arg branchUpdated "$branch_updated" --arg branchAfter "$branch_after" \
    --arg updateUnitResult "$update_result" --arg repairUnitResult "$repair_result" \
    --arg baseToplevel "$VM_TOPLEVEL" --arg variantToplevel "$variant" --arg disabledToplevel "$disabled" \
    '{schemaVersion:1,status:"pass",twoGenerations:true,baseToplevel:$baseToplevel,variantToplevel:$variantToplevel,disabledToplevel:$disabledToplevel,baseTarget:$baseTarget,variantTarget:$variantTarget,updatedWhileRecordedTargetLive:($linkedUpdated==$variantTarget),updateUnitResult:$updateUnitResult,updateLedgerAdvanced:($recordedUpdated==$variantTarget),updateRecordedBranch:$branchUpdated,inertAcrossIntermediateBoot:true,furnishUnitAbsentWhileInert:true,reapedByOrdinaryGc:true,ignoreLivenessUsed:false,repairedAfterGc:($linkedAfter==$baseTarget),repairUnitResult:$repairUnitResult,ledgerRecordAdvanced:($recordedAfter==$baseTarget),repairRecordedBranch:$branchAfter}' \
    | ssh_vm 'cat > /home/feltfomo/.cache/skadi-program-files-regression/furnish-gc-repair.json'
  log "two-generation proof: updated to $variant_target while it was live, repaired to $base_target after the reap"
}

vm_collect_evidence() {
  local destination="$1"
  mkdir -p "$destination"
  scp_from_vm "$VM_USER@localhost:/home/feltfomo/.cache/skadi-program-files-regression/*.json" "$destination/"
}

vm_equivalence() {
  local khion_matrix="$1" evidence="$2" output="$3" expected khion vm status
  local khion_expected vm_expected vm_khion boot_ids switches persistence generations fixtures gc_survival gc_repair migration release_probe ledger_survival all_true
  expected="$(expected_matrix | jq -Sc .)"
  khion="$(normalize_matrix "$khion_matrix" | jq -Sc .)"
  vm="$(normalize_matrix "$evidence/repair-matrix.json" | jq -Sc .)"
  khion_expected=false; vm_expected=false; vm_khion=false
  [ "$khion" = "$expected" ] && khion_expected=true
  [ "$vm" = "$expected" ] && vm_expected=true
  [ "$vm" = "$khion" ] && vm_khion=true
  boot_ids="$(jq -s 'length==3 and all(.[];.bootIdChanged==true and .homePersistence=="persisted")' "$evidence"/case-*-boot-evidence.json)"
  ledger_survival="$(jq -s 'length==3 and all(.[];.ledgerSurvived==true and .ledgerRecordStable==true)' "$evidence"/case-*-boot-evidence.json)"
  switches="$(jq -s 'length==3 and all(.[];.byteIdenticalToplevel==true)' "$evidence"/case-*-switch-evidence.json)"
  persistence="$(jq -s 'length==3 and all(.[];.negativeControlPassed==true and .persistedSentinelSurvived==true and .persistedSentinelUnchanged==true and .persistedEvidenceSetSurvived==true)' "$evidence"/case-*-persistence-evidence.json)"
  generations="$(jq -s 'length==3 and all(.[];.exactGenerationSelected==true and .systemRootPresent==true and .harnessRootPresent==true)' "$evidence"/case-*-generation-evidence.json)"
  fixtures="$(jq -s 'length==3 and all(.[];.fixtureStateValid==true)' "$evidence"/case-*-boot-evidence.json)"
  gc_survival="$(jq -e '.status=="pass" and .positiveGcRun==true and .exactTargetSurvived==true and .targetExistsAfterGc==true and .rootPresentAfter==true' "$evidence/furnish-gc-survival.json" >/dev/null && printf true || printf false)"
  gc_repair="$(jq -e '.status=="pass" and .twoGenerations==true and .updatedWhileRecordedTargetLive==true and .updateLedgerAdvanced==true and .updateRecordedBranch=="update" and .inertAcrossIntermediateBoot==true and .furnishUnitAbsentWhileInert==true and .reapedByOrdinaryGc==true and .ignoreLivenessUsed==false and .repairedAfterGc==true and .ledgerRecordAdvanced==true and .repairRecordedBranch=="repair"' "$evidence/furnish-gc-repair.json" >/dev/null && printf true || printf false)"
  migration="$(jq -e '.status=="pass" and .selfSmokePassed==true and .releaseEnabledEmpty==true and .releaseHandoff==true and .adoptTakeover==true and .adoptSelectedForBoot==true' "$evidence/furnish-migrate-gate.json" >/dev/null && printf true || printf false)"
  release_probe="$(jq -e '.runtimeModulePresent==true and .declarations==[] and .manifestData==[] and .manifestPath!=null and .hasActivation==true and .hasBootService==true' "$evidence/release-generation-probe.json" >/dev/null && printf true || printf false)"
  all_true=false
  if [ "$khion_expected" = true ] && [ "$vm_expected" = true ] && [ "$vm_khion" = true ] && [ "$boot_ids" = true ] && [ "$switches" = true ] && [ "$persistence" = true ] && [ "$generations" = true ] && [ "$fixtures" = true ] && [ "$gc_survival" = true ] && [ "$gc_repair" = true ] && [ "$migration" = true ] && [ "$release_probe" = true ] && [ "$ledger_survival" = true ]; then all_true=true; fi
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
    --argjson exactGenerationSelected "$generations" --argjson fixtureStates "$fixtures" --argjson positiveGcSurvival "$gc_survival" \
    --argjson twoGenerationGcRepair "$gc_repair" \
    --argjson releaseAdoptHandoff "$migration" --argjson releaseEnabledEmpty "$release_probe" \
    --argjson ledgerSurvivedRootWipe "$ledger_survival" \
    '{schemaVersion:1,status:$status,authority:{expectedMatrix:$expected},khionEvidence:{path:$khionMatrixPath,sha256:$khionMatrixSha256,modifiedAt:$khionMatrixModifiedAt,baselineGeneratedBy:$baselineGeneratedBy,baselineSystemToplevel:$baselineSystemToplevel,matrix:$khion},vmEvidence:{matrix:$vm,archive:$archive,testedToplevel:$testedToplevel,regressionApp:$regressionApp},invariants:{khionMatchesExpected:$khionMatchesExpected,vmMatchesExpected:$vmMatchesExpected,vmMatchesKhion:$vmMatchesKhion,changedBootIds:$changedBootIds,byteIdenticalNoOpSwitches:$byteIdenticalSwitches,persistenceAndNegativeControls:$persistenceControls,exactGenerationSelected:$exactGenerationSelected,fixtureStatesValid:$fixtureStates,positiveGcSurvival:$positiveGcSurvival,twoGenerationGcRepair:$twoGenerationGcRepair,releaseAdoptHandoff:$releaseAdoptHandoff,releaseEnabledEmpty:$releaseEnabledEmpty,ledgerSurvivedRootWipe:$ledgerSurvivedRootWipe}}' > "$output"
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
  VM_RELEASE_TOPLEVEL="$(vm_build_release_toplevel "$VM_TEST_FLAKE")"
  [ "$VM_RELEASE_TOPLEVEL" != "$VM_TOPLEVEL" ] || die "release and adopt generations are identical; no ownership handoff can be proved"
  log "built enabled-empty furnish release toplevel $VM_RELEASE_TOPLEVEL"
  VM_APP="$(nix build --no-link --print-out-paths "${VM_TEST_FLAKE}#program-files-regression")"
  archive_json="$(nix flake archive --json "$VM_TEST_FLAKE")"
  VM_ARCHIVE="$(jq -r .path <<<"$archive_json")"
  [[ "$VM_ARCHIVE" == /nix/store/* ]] || die "flake archive is not an immutable store path"
  vm_copy_closures
  migrate_smoke
  migrate_apply "$VM_RELEASE_TOPLEVEL"
  migrate_assert_release
  migrate_apply "$VM_TOPLEVEL"
  migrate_assert_adopt
  vm_select_toplevel
  vm_record_integrated_migration
  vm_reboot
  vm_assert_selected_after_boot initial
  vm_guest_harness furnish-symlink --host vm
  vm_gc_survival
  vm_guest_harness rm-matrix --host vm
  local mode
  for mode in absent dangling drifted; do
    vm_guest_harness case-prepare --host vm --mode "$mode"
    vm_noop_switch "$mode"
    vm_guest_harness case-switch-assert --host vm --mode "$mode"
    vm_guest_harness case-prepare --host vm --mode "$mode"
    vm_guest_harness_root reboot-prepare --host vm --mode "$mode" --run-id "$run_id"
    vm_reboot
    vm_assert_selected_after_boot "$mode"
    vm_guest_harness_root reboot-assert --host vm --mode "$mode" --run-id "$run_id"
    vm_guest_harness case-boot-assert --host vm --mode "$mode"
  done
  vm_gc_repair_survival "$VM_TEST_FLAKE" "$run_dir/variant-source"
  vm_collect_evidence "$evidence"
  cp "$CACHE/release-generation-probe.json" "$evidence/"
  cp "$CACHE/disabled-generation-probe.json" "$evidence/"
  cp "$evidence/repair-matrix.json" "$CACHE/vm-repair-matrix.json"
  vm_equivalence "$khion_matrix" "$evidence" "$output"
  log "VM proof passed; disposable overlay retained at $run_dir"
}

migrate_smoke() {
  # a false green is the real risk. unless the base truly starts pre-furnish with
  # hjem owning kitty.conf, the two-step handoff proves nothing.
  local path=/home/feltfomo/.config/kitty/kitty.conf raw
  ssh_vm test -L "$path" || die "self-smoke: base does not start with a managed kitty.conf symlink"
  raw="$(ssh_vm readlink -- "$path")"
  case "$raw" in
    *-skadi-*) ;;
    *) die "self-smoke: base kitty.conf is not a pre-furnish hjem target: $raw";;
  esac
  log "self-smoke: base starts pre-furnish, hjem owns kitty.conf ($raw)"
}

migrate_apply() {
  # test activation only; a probed generation must never become the boot default.
  local toplevel="$1" rc active
  vm_copy_toplevel "$toplevel"
  rc=0
  ssh_root "$toplevel/bin/switch-to-configuration" test || rc=$?
  # current-system moves even when a later unit fails, so this catches a skipped
  # activation while leaving unit-level failures to the per-generation asserts.
  active="$(ssh_vm readlink -f /run/current-system)"
  [ "$active" = "$toplevel" ] || die "guest did not activate $toplevel (current-system=$active, switch rc=$rc)"
}

migrate_assert_release() {
  # furnish is loaded with an empty desired set, so only hjem may release its prior link.
  local path=/home/feltfomo/.config/kitty/kitty.conf result errors
  result="$(ssh_root systemctl show -p Result --value hjem-activate@feltfomo.service)"
  [ "$result" = success ] || die "release: hjem-activate did not finish cleanly (Result=$result)"
  errors="$(ssh_root journalctl -b -u hjem-activate@feltfomo.service --no-pager | grep -c 'File is not the same as expected' || true)"
  [ "$errors" = 0 ] || die "release: hjem hit a teardown collision ($errors occurrences)"
  ! ssh_vm test -L "$path" || die "release: kitty.conf link survived hjem teardown"
  ! ssh_vm test -e "$path" || die "release: kitty.conf still present after hjem teardown"
  log "release generation handed kitty.conf back; hjem removed its own link"
}

migrate_assert_adopt() {
  # furnish now owns the path from absent; hjem must stay out of it.
  local path=/home/feltfomo/.config/kitty/kitty.conf target result errors
  ssh_vm test -L "$path" || die "adopt: furnish did not create the kitty.conf symlink"
  target="$(ssh_vm readlink -- "$path")"
  case "$target" in
    *furnish-kitty.conf) ;;
    *) die "adopt: kitty.conf points at $target, not the furnish artifact";;
  esac
  case "$target" in
    *-skadi-*) die "adopt: kitty.conf still points at a hjem target: $target";;
  esac
  ssh_vm test -e "$path" || die "adopt: furnish kitty.conf target is missing"
  result="$(ssh_root systemctl show -p Result --value hjem-activate@feltfomo.service)"
  [ "$result" = success ] || die "adopt: hjem-activate is not active (Result=$result)"
  errors="$(ssh_root journalctl -b -u hjem-activate@feltfomo.service --no-pager | grep -c 'File is not the same as expected' || true)"
  [ "$errors" = 0 ] || die "adopt: hjem attempted a kitty.conf teardown ($errors occurrences)"
  log "adopt generation took over kitty.conf; furnish target exact, hjem quiet"
}

migrate_gate() {
  # prove every pre-furnish base migrates deliberately. a release generation hands
  # kitty.conf back to hjem, then the adopt generation lets furnish take it over.
  # khion's own migration was accidental, so this is the only positive proof.
  local base="" release="" adopt="" run_id run_dir
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --base) base="$2"; shift 2;;
      --release-toplevel) release="$2"; shift 2;;
      --adopt-toplevel) adopt="$2"; shift 2;;
      *) die "unknown migrate-gate argument: $1";;
    esac
  done
  vm_require_run
  base="${base:-$VM_BASE}"
  [ -f "$base" ] || die "migration base image is missing: $base"
  [ -f "$VM_BASE_VARS" ] || die "lifecycle base vars are missing; run vm provision once"
  [ -n "$release" ] && [ -n "$adopt" ] || die "migrate-gate needs --release-toplevel and --adopt-toplevel"
  { [[ "$release" == /nix/store/* ]] && [ -e "$release" ]; } || die "release toplevel is not a live store path: $release"
  { [[ "$adopt" == /nix/store/* ]] && [ -e "$adopt" ]; } || die "adopt toplevel is not a live store path: $adopt"
  # identical generations can't demonstrate a handoff.
  [ "$release" != "$adopt" ] || die "release and adopt toplevels are identical; nothing to migrate"

  run_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
  run_dir="$VM_CACHE/program-files-migrate-$run_id"
  mkdir -p "$run_dir"
  VM_OVERLAY="$run_dir/disk.qcow2"
  VM_RUN_VARS="$run_dir/vars.fd"
  VM_SERIAL="$run_dir/serial.log"
  VM_CODE="$OVMF_FD/FV/OVMF_CODE.fd"
  qemu-img create -f qcow2 -F qcow2 -b "$base" "$VM_OVERLAY" >/dev/null
  cp "$VM_BASE_VARS" "$VM_RUN_VARS"
  chmod 0600 "$VM_RUN_VARS"
  QEMU_PID=""
  trap 'vm_stop' EXIT
  vm_start

  migrate_smoke
  migrate_apply "$release"
  migrate_assert_release
  migrate_apply "$adopt"
  migrate_assert_adopt

  jq -n --arg base "$base" --arg release "$release" --arg adopt "$adopt" \
    '{schemaVersion:1,status:"pass",base:$base,releaseToplevel:$release,adoptToplevel:$adopt,selfSmokePassed:true,releaseHandoff:true,adoptTakeover:true}' \
    > "$CACHE/furnish-migrate-gate.json"
  log "migration proof passed; disposable overlay retained at $run_dir"
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
  furnish-symlink)
    [ "${1:-}" = --host ] && [ -n "${2:-}" ] || die "furnish-symlink needs --host"
    furnish_symlink "$2";;
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
    action="${1:-}"; [ -n "$action" ] || die "vm needs provision, run, or migrate-gate"; shift
    if [ "$action" = migrate-gate ]; then migrate_gate "$@"; exit $?; fi
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
  fault-prepare|fault-assert)
    action="$command"; host=""; point=""; coordinator=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --host) host="$2"; shift 2;;
        --point) point="$2"; shift 2;;
        --coordinator) coordinator="$2"; shift 2;;
        *) die "unknown $action argument: $1";;
      esac
    done
    [ -n "$host" ] && [ -n "$point" ] && [ -n "$coordinator" ] || die "$action needs --host, --point, and --coordinator"
    if [ "$action" = fault-prepare ]; then fault_prepare "$host" "$point" "$coordinator"; else fault_assert "$host" "$point" "$coordinator"; fi
    ;;
  -h|--help|help) usage;;
  *) usage; exit 2;;
esac
