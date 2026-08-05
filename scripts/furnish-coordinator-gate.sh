#!/usr/bin/env bash
set -euo pipefail

repo="$(git rev-parse --show-toplevel)"
crate="$repo/modules/_lib/furnish/coordinator"
cd "$repo"

step() { printf '\n[coordinator-gate] %s\n' "$1"; }
die() { printf '[coordinator-gate] error  %s\n' "$*" >&2; exit 1; }
run() { step "$1"; shift; "$@"; }

capture_tests() {
  local name="$1" output="$2" minimum="$3" expected_results="$4"
  shift 4
  step "$name"
  set +e
  "$@" 2>&1 | tee "$output"
  local command_status="${PIPESTATUS[0]}"
  set -e

  local result_lines passed_terms failed_terms passed failed
  result_lines="$(grep -Ec '^test result: (ok|FAILED)\.' "$output" || true)"
  [ "$result_lines" -eq "$expected_results" ] \
    || die "$name produced $result_lines test result lines; expected $expected_results"
  passed_terms="$(sed -nE 's/^test result: (ok|FAILED)\. ([0-9]+) passed; ([0-9]+) failed;.*/\2/p' "$output")"
  failed_terms="$(sed -nE 's/^test result: (ok|FAILED)\. ([0-9]+) passed; ([0-9]+) failed;.*/\3/p' "$output")"
  [ -n "$passed_terms" ] && [ -n "$failed_terms" ] \
    || die "$name produced no parseable test result counts"
  passed="$(printf '%s\n' "$passed_terms" | paste -sd+ - | bc)"
  failed="$(printf '%s\n' "$failed_terms" | paste -sd+ - | bc)"
  [ "$failed" -eq 0 ] || die "$name reported $failed failed tests"
  [ "$command_status" -eq 0 ] || die "$name command exited $command_status"
  [ "$passed" -ge "$minimum" ] || die "$name regressed below $minimum passing tests"
  printf '[coordinator-gate] observed  passed=%s failed=%s minimum=%s result_lines=%s\n' \
    "$passed" "$failed" "$minimum" "$result_lines"
}

# creating the missing directory would turn an ordering refusal into hidden
# bootstrap behavior, so absence after the failed call is part of the result.
absent_lock_dir_proof() {
  local host="$1" coordinator="$2" case_dir manifest_path manifest missing diagnostic diagnostic_line status
  case_dir="$scratch/absent-lock-$host"
  manifest="$case_dir/manifest.json"
  missing="$case_dir/missing-lock"
  diagnostic="$case_dir/diagnostic.json"
  rm -rf "$case_dir"
  mkdir -p "$case_dir/state"
  manifest_path="$(nix eval --raw ".#nixosConfigurations.${host}.config.lexicon.furnish.manifestPath")"
  jq '.entries = []' "$manifest_path" > "$manifest"

  status=0
  "$coordinator" reconcile \
    --manifest "$manifest" \
    --lock-name absent.lock \
    --state-dir "$case_dir/state" \
    --setpriv "$(command -v setpriv)" \
    --lock-dir "$missing" 2> "$case_dir/stderr.log" || status=$?
  [ "$status" -ne 0 ] || die 'absent lock directory unexpectedly reconciled'
  diagnostic_line="$(grep -m1 -F '"message":"open-run-lock failed"' "$case_dir/stderr.log" || true)"
  [ -n "$diagnostic_line" ] || die 'absent lock directory emitted no open-run-lock diagnostic'
  printf '%s\n' "$diagnostic_line" > "$diagnostic"
  jq -e '.code == "runtime/invalid-manifest" and .cause.operation == "open-run-lock" and .cause.errno == 2' \
    "$diagnostic" >/dev/null || die 'absent lock directory emitted the wrong diagnostic'
  [ ! -e "$missing" ] || die 'coordinator created the absent lock directory'
  printf '[coordinator-gate] observed  lock_dir_created=0 operation=open-run-lock errno=2\n'
}

# matching shell text cannot show which branch executes. replace only the
# coordinator path with a scratch stub so both branches stay safe to run.
activation_guard_proof() {
  local host="$1" activation_text real_coordinator stub probe boot_output default_output
  activation_text="$scratch/activation-$host.sh"
  stub="$scratch/coordinator-stub-$host"
  probe="$scratch/activation-probe-$host.sh"
  nix eval --raw ".#nixosConfigurations.${host}.config.system.activationScripts.furnish.text" \
    > "$activation_text"
  real_coordinator="$(grep -Eo '/nix/store/[^[:space:]]+/bin/furnish-coordinator' "$activation_text" | head -n1)"
  [ -n "$real_coordinator" ] || die 'activation text contains no furnish coordinator command'
  printf '%s\n' '#!/usr/bin/env bash' "printf '%s\\n' reconcile-called" > "$stub"
  chmod +x "$stub"
  sed "s|$real_coordinator|$stub|g" "$activation_text" > "$probe"

  boot_output="$(env IN_NIXOS_SYSTEMD_STAGE1=true bash "$probe")"
  grep -Fqx 'furnish activation boot path defers reconciliation to furnish.service' <<<"$boot_output" \
    || die 'boot activation did not defer to the unit'
  if grep -Fqx reconcile-called <<<"$boot_output"; then
    die 'boot activation reached the coordinator'
  fi

  default_output="$(env -u IN_NIXOS_SYSTEMD_STAGE1 bash "$probe")"
  grep -Fqx reconcile-called <<<"$default_output" \
    || die 'activation without the boot mark did not reconcile'
  if grep -Fq 'defers reconciliation' <<<"$default_output"; then
    die 'activation without the boot mark took the defer branch'
  fi
  printf '[coordinator-gate] observed  activation_boot=deferred activation_default=reconciled\n'
}

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

# the gate certifies a host, so it must evaluate with that host's evaluator.
# bundling nix silently certified lumi under a nix the host did not run.
step 'host nix evaluator'
host_nix="$(command -v nix || true)"
[ -n "$host_nix" ] || die 'gate requires the host nix on PATH'
host_nix="$(readlink -f "$host_nix")"
host_nix_version="$("$host_nix" --version | paste -sd' ' -)"
printf '[coordinator-gate] evaluator  path=%s version=%s\n' "$host_nix" "$host_nix_version"

run 'rust formatter' nix develop -c cargo fmt --manifest-path "$crate/Cargo.toml" -- --check
run 'production compiler' nix develop -c cargo check --release --manifest-path "$crate/Cargo.toml"
run 'production clippy' nix develop -c cargo clippy --release --manifest-path "$crate/Cargo.toml" -- -D warnings
capture_tests 'default coordinator tests' "$scratch/default.log" 170 8 \
  nix develop -c cargo test --manifest-path "$crate/Cargo.toml"
capture_tests 'fault-injection coordinator tests' "$scratch/fault.log" 179 8 \
  nix develop -c cargo test --manifest-path "$crate/Cargo.toml" --features fault-injection
capture_tests 'crash recovery tests' "$scratch/crash-recovery.log" 8 1 \
  nix develop -c cargo test --manifest-path "$crate/Cargo.toml" --features fault-injection --test crash_recovery

step 'frozen integration test md5s'
printf '%s\n' \
  'fabf4b9da140655c60d55c564ff436bc  tests/characterization.rs' \
  'aa87e6cecd892b86db64bc094f387986  tests/cli.rs' \
  '1d57dd44d08b4fca6f878b01df5e9afa  tests/crash_recovery.rs' \
  '9c69bcd104bad8e2dccb4b862ee129c7  tests/diagnostics.rs' \
  '337e2a50592af569e8d17aca34e98c2c  tests/lifecycle.rs' \
  > "$scratch/tests.md5"
(
  cd "$crate"
  md5sum -c "$scratch/tests.md5"
)
printf '[coordinator-gate] observed  frozen_files=5 changed=0\n'

step 'suppressions and touched-file vocabulary'
suppression_pattern='#!?\[\s*(allow|expect)\s*\('
suppressions="$scratch/suppressions.txt"
grep -RPn "$suppression_pattern" "$crate/src" "$crate/tests" > "$suppressions" || true
suppression_count="$(wc -l < "$suppressions")"
[ "$suppression_count" -eq 5 ] \
  || die "suppression inventory expected 5 matches, found $suppression_count"
too_many_count="$(grep -Pc '#!?\[\s*(allow|expect)\s*\(\s*clippy::too_many_arguments\s*\)' "$suppressions" || true)"
[ "$too_many_count" -eq 5 ] \
  || die "suppression class expected 5 clippy::too_many_arguments matches, found $too_many_count"

assert_suppression_symbols() {
  local file="$1" expected="$2"
  shift 2
  local -a lines
  mapfile -t lines < <(grep -Pn "$suppression_pattern" "$file" | cut -d: -f1)
  [ "${#lines[@]}" -eq "$expected" ] \
    || die "suppression count for $file expected $expected, found ${#lines[@]}"
  local index line symbol next
  for index in "${!lines[@]}"; do
    line="${lines[$index]}"
    symbol="${1}"
    shift
    next="$(sed -n "$((line + 1)),\$ { /^[[:space:]]*\$/d; s/^[[:space:]]*//; p; q; }" "$file")"
    case "$next" in
      "fn $symbol("*) ;;
      *) die "suppression in $file is not attached to fn $symbol(" ;;
    esac
  done
}

reconcile="$crate/src/reconcile/mod.rs"
cfg_test_count="$(grep -Ec '^[[:space:]]*#\[cfg\(test\)\][[:space:]]*$' "$reconcile" || true)"
[ "$cfg_test_count" -eq 1 ] \
  || die "reconcile cfg(test) count expected 1, found $cfg_test_count"
cfg_test_line="$(grep -En '^[[:space:]]*#\[cfg\(test\)\][[:space:]]*$' "$reconcile" | cut -d: -f1)"
mapfile -t reconcile_suppression_lines < <(grep -Pn "$suppression_pattern" "$reconcile" | cut -d: -f1)
[ "${#reconcile_suppression_lines[@]}" -eq 2 ] \
  || die "reconcile suppression count expected 2, found ${#reconcile_suppression_lines[@]}"
for line in "${reconcile_suppression_lines[@]}"; do
  [ "$line" -gt "$cfg_test_line" ] \
    || die "reconcile suppression at line $line is outside the cfg(test) module"
done
assert_suppression_symbols "$reconcile" 2 plant_record plant_pending_with_prior
assert_suppression_symbols "$crate/tests/crash_recovery.rs" 2 record_json prior_owned_json
assert_suppression_symbols "$crate/tests/lifecycle.rs" 1 record_json

if grep -RInE '\bSP[0-9]+\b|\bsub-phase\b|\bruling\b|\broadmap\b' \
  "$crate/src" "$repo/scripts/furnish-coordinator-gate.sh" \
  "$repo/tests/program-files-regression.sh" "$repo/modules/tools/furnish-coordinator-gate.nix"; then
  die 'process vocabulary found in touched production sources or gate files'
fi
printf '[coordinator-gate] observed  suppressions=%s too_many_arguments=%s vocabulary_matches=0\n' \
  "$suppression_count" "$too_many_count"

format_repo="$scratch/format-repo"
mkdir "$format_repo"
cp -a --reflink=auto "$repo/." "$format_repo/"
step 'isolated nix formatter first pass'
first_format_output="$scratch/format-first.log"
(
  cd "$format_repo"
  nix fmt
) 2>&1 | tee "$first_format_output"
grep -Eq 'formatted [0-9]+ files \(0 changed\)' "$first_format_output" \
  || die 'isolated first formatter pass changed files or reported no count'
step 'isolated nix formatter second pass'
second_format_output="$scratch/format-second.log"
(
  cd "$format_repo"
  nix fmt
) 2>&1 | tee "$second_format_output"
grep -Eq 'formatted [0-9]+ files \(0 changed\)' "$second_format_output" \
  || die 'isolated second formatter pass did not report zero changed files'
printf '[coordinator-gate] observed  formatter_first_pass_changed=0 formatter_second_pass_changed=0\n'

run 'flake check' nix flake check -L
run 'coordinator release build' nix build -L .#furnish-coordinator
run 'default coordinator release check' nix build -L .#checks.x86_64-linux.furnish-coordinator
run 'fault-injection coordinator release check' nix build -L .#checks.x86_64-linux.furnish-coordinator-fault-injection
run 'fault boundary check' nix build -L .#checks.x86_64-linux.furnish-fault-injection-boundary
run 'runtime refusal smoke check' nix build -L .#checks.x86_64-linux.furnish-runtime
run 'treefmt check' nix build -L .#checks.x86_64-linux.treefmt
run 'program-files regression package' nix build -L .#program-files-regression
run 'khion toplevel' nix build -L .#nixosConfigurations.khion.config.system.build.toplevel
run 'lumi toplevel' nix build -L .#nixosConfigurations.lumi.config.system.build.toplevel

activation="${FURNISH_COORDINATOR_ACTIVATE:-0}"
case "$activation" in
  0|1) ;;
  *) die 'FURNISH_COORDINATOR_ACTIVATE must be 0 or 1' ;;
esac

host="$(hostnamectl --static 2>/dev/null || printf 'unknown')"
case "$host" in
  khion|lumi) ;;
  *) die "unsupported gate host: $host" ;;
esac

production_coordinator="$(nix build --no-link --print-out-paths .#furnish-coordinator)/bin/furnish-coordinator"
fault_coordinator="$(nix build --no-link --print-out-paths .#checks.x86_64-linux.furnish-coordinator-fault-injection)/bin/furnish-coordinator"
run 'absent lock directory refusal' absent_lock_dir_proof "$host" "$production_coordinator"
run 'activation boot guard' activation_guard_proof "$host"
run "$host exact furnish target" nix run .#program-files-regression -- furnish-symlink --host "$host"
run "$host retained-target roots" nix run .#program-files-regression -- roots --host "$host"
run "$host runtime-wins scratch proof" nix run .#program-files-regression -- runtime-wins-proof --host "$host" --coordinator "$production_coordinator"

fault_pairs=0
for point in pre-pending pending-committed stage-written stage-synced published published-synced verified exchange-published; do
  run "fault prepare: $point" nix run .#program-files-regression -- fault-prepare --host "$host" --point "$point" --coordinator "$fault_coordinator"
  run "fault assert: $point" nix run .#program-files-regression -- fault-assert --host "$host" --point "$point" --coordinator "$fault_coordinator"
  fault_pairs=$((fault_pairs + 1))
done
[ "$fault_pairs" -eq 8 ] || die "host coverage produced $fault_pairs fault pairs"

if [ "$activation" -eq 1 ]; then
  run "$host activation test" /run/wrappers/bin/sudo nixos-rebuild test --flake "$repo#$host"
else
  step "$host activation skipped; activation is disabled"
fi

printf '[coordinator-gate] coverage  {"host":"%s","hostChecks":"ran","faultPairs":%s}\n' \
  "$host" "$fault_pairs"
printf '\n[coordinator-gate] complete  host=%s activation=%s\n' "$host" "$activation"