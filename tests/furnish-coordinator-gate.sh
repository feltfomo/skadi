#!/usr/bin/env bash
set -euo pipefail

repo="$(git rev-parse --show-toplevel)"
cd "$repo"

# the crate is furnish-coordinator's repo now, so cargo, the frozen test md5s and
# the suppression inventory gate there. this gates what only khion can prove.

step() { printf '\n[coordinator-gate] %s\n' "$1"; }
die() { printf '[coordinator-gate] error  %s\n' "$*" >&2; exit 1; }
run() { step "$1"; shift; "$@"; }

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

step 'gate vocabulary'
if grep -RInE '\bSP[0-9]+\b|\bsub-phase\b|\bruling\b|\broadmap\b' \
  "$repo/tests/furnish-coordinator-gate.sh" \
  "$repo/tests/program-files-regression.sh" "$repo/modules/tools/furnish-coordinator-gate.nix"; then
  die 'process vocabulary found in the gate files'
fi
printf '[coordinator-gate] observed  vocabulary_matches=0\n'

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
run 'fault-injection coordinator build' nix build -L .#furnish-coordinator-fault-injection
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
fault_coordinator="$(nix build --no-link --print-out-paths .#furnish-coordinator-fault-injection)/bin/furnish-coordinator"
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