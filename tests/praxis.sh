# the check supplies a dispatcher and a mock nix, so no host is activated.
mkdir -p "$TMPDIR/mock"
export PRAXIS_TEST_LOG="$TMPDIR/calls"
export PATH="$TMPDIR/mock:$PATH"
printf '#!%s\n' "$(command -v bash)" >"$TMPDIR/mock/nix"
cat >>"$TMPDIR/mock/nix" <<'MOCK'
printf '%s' "$PWD" >> "$PRAXIS_TEST_LOG"
printf ' <%s>' "$@" >> "$PRAXIS_TEST_LOG"
printf '\n' >> "$PRAXIS_TEST_LOG"
if [[ ${PRAXIS_TEST_FAIL_CHECK:-0} == 1 && $* == 'flake check -L' ]]; then
  exit 42
fi
MOCK
chmod +x "$TMPDIR/mock/nix"
cd "$TMPDIR" || exit

"$PRAXIS" --plain --yes rebuild khion -- --dry
printf '%s\n' \
	'/tmp <run> <.#write-flake>' \
	'/tmp <fmt>' \
	'/tmp <flake> <check> <-L>' \
	'/tmp <run> <.#khion> <--> <switch> <--dry>' >expected
diff -u expected "$PRAXIS_TEST_LOG"

: >"$PRAXIS_TEST_LOG"
"$PRAXIS" --plain --yes rebuild lumi
sed 's/khion/lumi/; s/ <--dry>//' expected >expected-lumi
diff -u expected-lumi "$PRAXIS_TEST_LOG"

: >"$PRAXIS_TEST_LOG"
"$PRAXIS" --plain check --no-build
"$PRAXIS" --plain update input lexicon
"$PRAXIS" --plain flake update
printf '%s\n' \
	'/tmp <flake> <check> <-L> <--no-build>' \
	'/tmp <flake> <update> <lexicon>' \
	'/tmp <flake> <update>' >expected
diff -u expected "$PRAXIS_TEST_LOG"

: >"$PRAXIS_TEST_LOG"
for args in 'rebuild generic' 'rebuild' 'update input missing' 'update wrong lexicon' 'flake wrong'; do
	read -r -a argv <<<"$args"
	if "$PRAXIS" --plain --yes "${argv[@]}"; then
		echo "unexpected success: $args" >&2
		exit 1
	fi
done
test ! -s "$PRAXIS_TEST_LOG"

export PRAXIS_TEST_FAIL_CHECK=1
if "$PRAXIS" --plain --yes rebuild khion; then
	echo 'rebuild ignored a failed check' >&2
	exit 1
fi
printf '%s\n' \
	'/tmp <run> <.#write-flake>' \
	'/tmp <fmt>' \
	'/tmp <flake> <check> <-L>' >expected
diff -u expected "$PRAXIS_TEST_LOG"
echo 'praxis: 11 boundary cases passed'
