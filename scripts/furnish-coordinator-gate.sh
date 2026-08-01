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

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

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
  "$crate/src" "$repo/scripts/furnish-coordinator-gate.sh" "$repo/modules/furnish-coordinator-gate.nix"; then
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
  khion)
    run 'khion exact furnish target' nix run .#program-files-regression -- furnish-symlink --host khion
    run 'khion retained-target roots' nix run .#program-files-regression -- roots --host khion
    fault_coordinator="$(nix build --no-link --print-out-paths .#checks.x86_64-linux.furnish-coordinator-fault-injection)/bin/furnish-coordinator"
    for point in pre-pending pending-committed stage-written stage-synced published published-synced verified exchange-published; do
      run "fault prepare: $point" nix run .#program-files-regression -- fault-prepare --host khion --point "$point" --coordinator "$fault_coordinator"
      run "fault assert: $point" nix run .#program-files-regression -- fault-assert --host khion --point "$point" --coordinator "$fault_coordinator"
    done
    if [ "$activation" -eq 1 ]; then
      run 'khion activation test' /run/wrappers/bin/sudo nixos-rebuild test --flake "$repo#khion"
    else
      step 'khion activation skipped; set FURNISH_COORDINATOR_ACTIVATE=1 with router authorization'
    fi
    ;;
  lumi)
    if [ "$activation" -eq 1 ]; then
      run 'lumi activation test' /run/wrappers/bin/sudo nixos-rebuild test --flake "$repo#lumi"
    else
      step 'lumi activation skipped; set FURNISH_COORDINATOR_ACTIVATE=1 with router authorization'
    fi
    ;;
  *)
    step "host-specific checks and activation skipped on $host"
    ;;
esac

printf '\n[coordinator-gate] complete  host=%s activation=%s\n' "$host" "$activation"