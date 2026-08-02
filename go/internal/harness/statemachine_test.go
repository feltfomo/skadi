package harness

import (
	"context"
	"errors"
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// fakeRunner returns preprogrammed output for each command, streaming lines to
// the watcher so the live emergency stop can be exercised without nix.
type fakeRunner struct {
	responder func(spec CmdSpec) (lines []string, exit int)
}

func (f fakeRunner) Run(ctx context.Context, spec CmdSpec, watch LineWatcher) CmdResult {
	lines, exit := f.responder(spec)
	var b strings.Builder
	for _, ln := range lines {
		b.WriteString(ln)
		b.WriteByte('\n')
		if watch != nil {
			if err := watch(ln); err != nil {
				// Fake mirrors stdout into Combined; the real stream split is covered
				// by the ExecRunner tests below.
				return CmdResult{Combined: b.String(), Stdout: b.String(), ExitCode: -1, Err: err}
			}
		}
		if ctx.Err() != nil {
			return CmdResult{Combined: b.String(), Stdout: b.String(), ExitCode: -1, Err: ctx.Err()}
		}
	}
	return CmdResult{Combined: b.String(), Stdout: b.String(), ExitCode: exit}
}

func testHarness(t *testing.T, runner Runner) *Harness {
	t.Helper()
	dir := t.TempDir()
	cfg := Config{
		Rev:         "d33f37a59aee",
		Host:        "vm",
		StateDir:    dir,
		EvidenceDir: dir + "/evidence",
		CacheDir:    dir + "/cache",
		Subcommand:  "gate",
	}
	return New(cfg, runner, log.New(io.Discard, "", 0))
}

// These constants serve the static signed cache-closure proof for both explicit
// roots. `nix derivation show` yields each out path, then `nix path-info` against
// `file://<cache>` must return a complete recursive closure whose every path is
// signed by the per-rev key.
const (
	gateDrv      = "/nix/store/dddd0000dddd0000dddd0000dddd0000-nixos-system-vm.drv"
	gateOutPath  = "/nix/store/qr05v34zqr05v34zqr05v34zqr05v34z-nixos-system-vm-26.05"
	gateDiskoDrv = "/nix/store/eeee0000eeee0000eeee0000eeee0000-disko.drv"
	gateDiskoOut = "/nix/store/ss05v34zss05v34zss05v34zss05v34z-disko"
	gateDep      = "/nix/store/aaaa1111aaaa1111aaaa1111aaaa1111-glibc-2.39"
)

// gateRunner answers `nix derivation show` for both explicit roots and
// `nix path-info` with the supplied JSON body and exit code.
func gateRunner(pathInfoJSON string, pathInfoExit int) fakeRunner {
	return fakeRunner{responder: func(spec CmdSpec) ([]string, int) {
		if len(spec.Args) > 1 && spec.Args[0] == "derivation" {
			drv, out := gateDrv, gateOutPath
			if len(spec.Args) > 2 && spec.Args[2] == gateDiskoDrv {
				drv, out = gateDiskoDrv, gateDiskoOut
			}
			return []string{fmt.Sprintf(`{%q:{"outputs":{"out":{"path":%q}}}}`, drv, out)}, 0
		}
		if len(spec.Args) > 0 && spec.Args[0] == "path-info" {
			return []string{pathInfoJSON}, pathInfoExit
		}
		return nil, 0
	}}
}

func signedGateClosure(key string) string {
	return fmt.Sprintf(`[{"path":%q,"signatures":[%q]},{"path":%q,"signatures":[%q]},{"path":%q,"signatures":[%q]}]`,
		gateOutPath, key+":sigA==", gateDiskoOut, key+":sigB==", gateDep, key+":sigC==")
}

// a complete closure with every path signed by the per-rev key passes the static gate.
func TestBuildPlanGatePassesFullySignedClosure(t *testing.T) {
	h := testHarness(t, nil)
	key := h.cache.KeyName()
	body := signedGateClosure(key)
	h.runner = gateRunner(body, 0)
	h.manifest.DrvPaths = map[string]string{"toplevel": gateDrv, "disko": gateDiskoDrv}
	if err := h.stageStaticBuildPlanGate(context.Background()); err != nil {
		t.Fatalf("expected a fully-signed closure to pass, got %v", err)
	}
	if h.manifest.StorePaths["toplevel"] != gateOutPath || h.manifest.StorePaths["disko"] != gateDiskoOut {
		t.Fatalf("static gate did not record both roots: %v", h.manifest.StorePaths)
	}
}

func TestStaticBuildPlanGatePreservesExistingMeasurements(t *testing.T) {
	h := testHarness(t, nil)
	key := h.cache.KeyName()
	body := signedGateClosure(key)
	h.runner = gateRunner(body, 0)
	h.manifest.DrvPaths = map[string]string{"toplevel": gateDrv, "disko": gateDiskoDrv}
	h.manifest.GateBuildCount = intPtr(17)
	h.manifest.GateFetchCount = intPtr(19)
	if err := h.stageStaticBuildPlanGate(context.Background()); err != nil {
		t.Fatalf("static gate failed %v", err)
	}
	if h.manifest.GateBuildCount == nil || *h.manifest.GateBuildCount != 17 || h.manifest.GateFetchCount == nil || *h.manifest.GateFetchCount != 19 {
		t.Fatalf("observed counts changed to builds=%v fetches=%v", h.manifest.GateBuildCount, h.manifest.GateFetchCount)
	}
}

// the production gate must reach the merged copy/build half after both static
// root proofs pass, preserving the non-vacuous "fetched zero paths" assertion.
func TestBuildPlanGateCompositionReachesCopyFailure(t *testing.T) {
	h := testHarness(t, nil)
	if err := os.MkdirAll(h.cfg.EvidenceDir, 0o755); err != nil {
		t.Fatal(err)
	}
	key := h.cache.KeyName()
	body := signedGateClosure(key)
	h.manifest.DrvPaths = map[string]string{"toplevel": gateDrv, "disko": gateDiskoDrv}
	h.cfg.TrustedPublicKey = key + ":dGVzdA=="
	h.runner = fakeRunner{responder: func(spec CmdSpec) ([]string, int) {
		if len(spec.Args) > 1 && spec.Args[0] == "derivation" {
			drv, out := gateDrv, gateOutPath
			if len(spec.Args) > 2 && spec.Args[2] == gateDiskoDrv {
				drv, out = gateDiskoDrv, gateDiskoOut
			}
			return []string{fmt.Sprintf(`{%q:{"outputs":{"out":{"path":%q}}}}`, drv, out)}, 0
		}
		if len(spec.Args) > 0 && spec.Args[0] == "path-info" && slicesContain(spec.Args, "--recursive") {
			return []string{body}, 0
		}
		if slicesContain(spec.Args, "--all") {
			return []string{"[]"}, 0
		}
		if len(spec.Args) > 0 && spec.Args[0] == "copy" {
			return nil, 0
		}
		return nil, 1
	}}
	err := h.stageBuildPlanGate(context.Background())
	if err == nil {
		t.Fatal("production gate skipped the copy failure")
	}
	if !strings.Contains(err.Error(), "fetched zero paths") {
		t.Fatalf("composition failed before the copy scan: %v", err)
	}
}

// (ii) path-info exits nonzero when a referenced path is missing from the signed
// cache; the gate must fail closed.
func TestBuildPlanGateFailsMissingClosurePath(t *testing.T) {
	h := testHarness(t, nil)
	h.runner = gateRunner(`error: path '/nix/store/missing' is not valid`, 1)
	h.manifest.DrvPaths = map[string]string{"toplevel": gateDrv, "disko": gateDiskoDrv}
	if err := h.stageStaticBuildPlanGate(context.Background()); err == nil {
		t.Fatal("expected gate to fail closed when the cached closure is incomplete")
	}
}

// (iii) A closure path signed only by a non-trusted (golden) key must fail
// closed.
func TestBuildPlanGateFailsUntrustedSignature(t *testing.T) {
	h := testHarness(t, nil)
	key := h.cache.KeyName()
	body := fmt.Sprintf(`[{"path":%q,"signatures":[%q]},{"path":%q,"signatures":[%q]},{"path":%q,"signatures":[%q]}]`,
		gateOutPath, key+":sigA==", gateDiskoOut, key+":sigB==", gateDep, "skadi-golden-cafebabe:sigX==")
	h.runner = gateRunner(body, 0)
	h.manifest.DrvPaths = map[string]string{"toplevel": gateDrv, "disko": gateDiskoDrv}
	if err := h.stageStaticBuildPlanGate(context.Background()); err == nil {
		t.Fatal("expected gate to fail closed on an untrusted signature")
	}
}

func TestCheckoutPreparedRevisionFetchesRemoteTrackingOnlyCommit(t *testing.T) {
	ctx := context.Background()
	source := t.TempDir()
	runGit := func(dir string, args ...string) string {
		t.Helper()
		res := ExecRunner{}.Run(ctx, CmdSpec{Name: "git", Args: args, Dir: dir}, nil)
		if res.Err != nil || res.ExitCode != 0 {
			t.Fatalf("git %s in %s exit=%d err=%v\n%s", strings.Join(args, " "), dir, res.ExitCode, res.Err, res.Combined)
		}
		return strings.TrimSpace(res.Stdout)
	}

	runGit(source, "init", "--quiet")
	runGit(source, "config", "user.name", "Harness Test")
	runGit(source, "config", "user.email", "harness-test@example.invalid")
	if err := os.WriteFile(filepath.Join(source, "remote-only"), []byte("remote-only revision\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	runGit(source, "add", "remote-only")
	runGit(source, "commit", "--quiet", "-m", "remote-only revision")
	remoteOnlyRev := runGit(source, "rev-parse", "HEAD")
	runGit(source, "update-ref", "refs/remotes/origin/main", remoteOnlyRev)

	runGit(source, "checkout", "--quiet", "--orphan", "active")
	runGit(source, "rm", "--quiet", "--cached", "remote-only")
	if err := os.Remove(filepath.Join(source, "remote-only")); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(source, "active"), []byte("active lineage\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	runGit(source, "add", "active")
	runGit(source, "commit", "--quiet", "-m", "active lineage")
	for _, branch := range strings.Fields(runGit(source, "for-each-ref", "--format=%(refname:short)", "refs/heads")) {
		if branch != "active" {
			runGit(source, "branch", "-D", branch)
		}
	}

	if got := runGit(source, "branch", "--contains", remoteOnlyRev); got != "" {
		t.Fatalf("remote-only revision unexpectedly has a local branch %q", got)
	}
	if got := runGit(source, "branch", "-r", "--contains", remoteOnlyRev); !strings.Contains(got, "origin/main") {
		t.Fatalf("remote-only revision is not observable through origin/main %q", got)
	}

	h := testHarness(t, ExecRunner{})
	h.repoRoot = source
	h.manifest.Rev = remoteOnlyRev
	prepared := filepath.Join(t.TempDir(), "prepared")
	if err := h.checkoutPreparedRevision(ctx, prepared); err != nil {
		t.Fatalf("checkoutPreparedRevision %v", err)
	}
	if got := runGit(prepared, "rev-parse", "HEAD"); got != remoteOnlyRev {
		t.Fatalf("prepared HEAD %q observed source revision %q", got, remoteOnlyRev)
	}
}

func TestCreateRunDirRetainsPriorRunEvidence(t *testing.T) {
	root := t.TempDir()
	cacheDir := filepath.Join(t.TempDir(), "cache")
	if err := os.Mkdir(cacheDir, 0o755); err != nil {
		t.Fatal(err)
	}
	cacheMarker := filepath.Join(cacheDir, "shared-cache-marker")
	if err := os.WriteFile(cacheMarker, []byte("shared"), 0o644); err != nil {
		t.Fatal(err)
	}

	started := time.Date(2026, 7, 29, 17, 30, 0, 0, time.UTC)
	first, err := CreateRunDir(root, "0123456789abcdef", "gate", started)
	if err != nil {
		t.Fatal(err)
	}
	firstReport := filepath.Join(first, "report.json")
	if err := os.WriteFile(firstReport, []byte("first report"), 0o644); err != nil {
		t.Fatal(err)
	}
	firstPrepared := filepath.Join(first, "prepared-source")
	if err := os.Mkdir(firstPrepared, 0o755); err != nil {
		t.Fatal(err)
	}
	firstPreparedMarker := filepath.Join(firstPrepared, "retained")
	if err := os.WriteFile(firstPreparedMarker, []byte("first source"), 0o644); err != nil {
		t.Fatal(err)
	}

	second, err := CreateRunDir(root, "0123456789abcdef", "gate", started.Add(time.Second))
	if err != nil {
		t.Fatal(err)
	}
	if first == second {
		t.Fatalf("two invocations reused %s", first)
	}
	for _, retained := range []string{firstReport, firstPreparedMarker, cacheMarker} {
		if _, err := os.Stat(retained); err != nil {
			t.Fatalf("retained evidence %s %v", retained, err)
		}
	}
	if _, err := os.Stat(second); err != nil {
		t.Fatalf("second run directory %v", err)
	}
}

func TestCreateRunDirTreatsExplicitRootAsRetentionRoot(t *testing.T) {
	explicitRoot := filepath.Join(t.TempDir(), "explicit-evidence")
	started := time.Date(2026, 7, 29, 17, 31, 0, 0, time.UTC)
	first, err := CreateRunDir(explicitRoot, "fedcba9876543210", "check", started)
	if err != nil {
		t.Fatal(err)
	}
	marker := filepath.Join(first, "report.txt")
	if err := os.WriteFile(marker, []byte("explicit first"), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := CreateRunDir(explicitRoot, "fedcba9876543210", "check", started.Add(time.Second)); err != nil {
		t.Fatal(err)
	}
	if got, err := os.ReadFile(marker); err != nil || string(got) != "explicit first" {
		t.Fatalf("explicit-root evidence changed got=%q err=%v", got, err)
	}
}

func TestCreateRunDirRefusesExistingLeaf(t *testing.T) {
	root := t.TempDir()
	started := time.Date(2026, 7, 29, 17, 32, 0, 0, time.UTC)
	first, err := CreateRunDir(root, "aaaaaaaaaaaa1111", "build-cache", started)
	if err != nil {
		t.Fatal(err)
	}
	marker := filepath.Join(first, "retained")
	if err := os.WriteFile(marker, []byte("original"), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := CreateRunDir(root, "aaaaaaaaaaaa1111", "build-cache", started); err == nil {
		t.Fatal("existing run leaf was reused")
	}
	if got, err := os.ReadFile(marker); err != nil || string(got) != "original" {
		t.Fatalf("collision changed retained evidence got=%q err=%v", got, err)
	}
}

func TestNewRecordsResolvedRunDirectory(t *testing.T) {
	runDir := filepath.Join(t.TempDir(), "resolved-run")
	h := New(Config{Rev: "abc", StateDir: t.TempDir(), EvidenceDir: runDir, CacheDir: t.TempDir(), Subcommand: "check"}, nil, nil)
	if h.manifest.RunDir != runDir {
		t.Fatalf("manifest recorded run directory %q", h.manifest.RunDir)
	}
	if !strings.Contains(h.manifest.Human(), "run dir:     "+runDir) {
		t.Fatalf("human report omitted run directory %q", runDir)
	}
}

// stagesFor must reject an unknown subcommand rather than default to something
// destructive.
func TestStagesForUnknownSubcommand(t *testing.T) {
	h := testHarness(t, fakeRunner{responder: func(CmdSpec) ([]string, int) { return nil, 0 }})
	if _, err := h.stagesFor("wipe-everything"); err == nil {
		t.Fatal("expected unknown subcommand to be rejected")
	}
}

// The full pipeline must place the destructive stages behind the confirm gate.
func TestAllStagesOrderingConfirmBeforeProvision(t *testing.T) {
	h := testHarness(t, fakeRunner{responder: func(CmdSpec) ([]string, int) { return nil, 0 }})
	stages, err := h.stagesFor("all")
	if err != nil {
		t.Fatalf("stagesFor(all): %v", err)
	}
	idx := map[string]int{}
	for i, s := range stages {
		idx[s.name] = i
	}
	for _, name := range []string{"prepare-source", "signing-key", "export-sign", "cache-check", "build-plan-gate", "serve-cache", "guest-launch", "confirm-gate", "guest-provision"} {
		if _, ok := idx[name]; !ok {
			t.Fatalf("missing stage %q in the full pipeline", name)
		}
	}
	if idx["confirm-gate"] >= idx["guest-provision"] {
		t.Fatalf("confirm-gate (%d) must precede guest-provision (%d)", idx["confirm-gate"], idx["guest-provision"])
	}
	// M1: a from-scratch `all` must build + sign the cache before it validates and
	// gates it, and the gate needs the signing-key public half; serve-cache (guest
	// HTTP) must precede the guest stages.
	if !(idx["prepare-source"] < idx["eval-drv"] && idx["eval-drv"] < idx["signing-key"] && idx["signing-key"] < idx["export-sign"] && idx["export-sign"] < idx["cache-check"] && idx["cache-check"] < idx["build-plan-gate"]) {
		t.Fatalf("expected prepare-source < eval-drv < signing-key < export-sign < cache-check < build-plan-gate, got %v", idx)
	}
	if idx["build-plan-gate"] >= idx["serve-cache"] || idx["serve-cache"] >= idx["guest-launch"] {
		t.Fatalf("expected build-plan-gate < serve-cache < guest-launch, got %v", idx)
	}
	if len(stages) != 17 {
		t.Fatalf("expected 17 stages in the full pipeline, got %d", len(stages))
	}
}

func TestEvalBearingSubcommandsIncludePrepareSource(t *testing.T) {
	h := testHarness(t, fakeRunner{responder: func(CmdSpec) ([]string, int) { return nil, 0 }})
	for _, sub := range []string{"check", "gate", "build-cache", "provision", "all"} {
		stages, err := h.stagesFor(sub)
		if err != nil {
			t.Fatalf("stagesFor(%s): %v", sub, err)
		}
		idx := map[string]int{}
		for i, s := range stages {
			idx[s.name] = i
		}
		if idx["prepare-source"] != idx["resolve-rev"]+1 {
			t.Fatalf("%s: prepare-source must follow resolve-rev, got %v", sub, idx)
		}
		if idx["eval-drv"] != idx["prepare-source"]+1 {
			t.Fatalf("%s: eval-drv must follow prepare-source, got %v", sub, idx)
		}
	}
}

// eval-drv must store exactly the single stdout drv path.
func TestEvalDrvStoresCleanStdoutPath(t *testing.T) {
	want := "/nix/store/aaa1111bbbb2222cccc3333dddd4444eeee5555-nixos-system-vm-26.05.drv"
	prepared := t.TempDir()
	var evalAttrs []string
	runner := fakeRunner{responder: func(spec CmdSpec) ([]string, int) {
		if spec.Name == "bash" {
			wantEnv := "SKADI_INSTALL_SOURCE=" + prepared
			if len(spec.Env) != 1 || spec.Env[0] != wantEnv {
				t.Fatalf("installer probe env = %v, want [%s]", spec.Env, wantEnv)
			}
			return []string{"[skadi-install] using pre-staged pinned source", "resolved: skadi-install vm", "drvPath: " + want}, 0
		}
		if spec.Name == "nix" && len(spec.Args) == 3 && spec.Args[0] == "eval" {
			evalAttrs = append(evalAttrs, spec.Args[2])
		}
		return []string{want}, 0
	}}
	h := testHarness(t, runner)
	h.preparedSource = prepared
	if err := h.stageEvalDrv(context.Background()); err != nil {
		t.Fatalf("expected clean stdout drv to be accepted, got %v", err)
	}
	if got := h.manifest.DrvPaths["toplevel"]; got != want {
		t.Fatalf("stored drv = %q, want %q", got, want)
	}
	if len(evalAttrs) != 2 || !strings.HasSuffix(evalAttrs[1], "#nixosConfigurations.vm.config.system.build._cliDestroyFormatMount.drvPath") {
		t.Fatalf("disko eval did not select the cli destroy-format-mount derivation: %v", evalAttrs)
	}
}

// A multi-line captured value (stderr warnings ahead of the drv -- the original
// bug) must be rejected fail-closed rather than poisoning export-sign.
func TestEvalDrvRejectsPoisonedOutput(t *testing.T) {
	runner := fakeRunner{responder: func(spec CmdSpec) ([]string, int) {
		return []string{
			"warning: fetching git input",
			"Using saved setting for 'extra-substituters'",
			"/nix/store/aaa1111bbbb2222cccc3333dddd4444eeee5555-nixos-system-vm-26.05.drv",
		}, 0
	}}
	h := testHarness(t, runner)
	h.preparedSource = t.TempDir()
	if err := h.stageEvalDrv(context.Background()); err == nil {
		t.Fatal("expected eval-drv to reject multi-line (poisoned) output")
	}
	if got := h.manifest.DrvPaths["toplevel"]; got != "" {
		t.Fatalf("poisoned drv must not be stored, got %q", got)
	}
}

// ExecRunner must expose stdout separately from the interleaved Combined view.
func TestExecRunnerStdoutStderrSplit(t *testing.T) {
	res := ExecRunner{}.Run(context.Background(),
		CmdSpec{Name: "sh", Args: []string{"-c", "echo warn-on-stderr >&2; printf '/nix/store/zzz-real.drv'"}}, nil)
	if res.Err != nil || res.ExitCode != 0 {
		t.Fatalf("unexpected failure: exit=%d err=%v", res.ExitCode, res.Err)
	}
	if got := strings.TrimSpace(res.Stdout); got != "/nix/store/zzz-real.drv" {
		t.Fatalf("Stdout must contain only stdout, got %q", got)
	}
	if !strings.Contains(res.Combined, "warn-on-stderr") || !strings.Contains(res.Combined, "/nix/store/zzz-real.drv") {
		t.Fatalf("Combined must interleave both streams, got %q", res.Combined)
	}
}

// After the split the watcher must still scan STDERR: a build line printed to
// stderr must trip the emergency stop (guards against watching stdout only).
func TestExecRunnerWatcherSeesStderr(t *testing.T) {
	res := ExecRunner{}.Run(context.Background(),
		CmdSpec{Name: "sh", Args: []string{"-c", "echo \"building '/nix/store/zzz-thing.drv'...\" >&2; sleep 30; echo late"}},
		buildGateWatcher(nil))
	if !errors.Is(res.Err, ErrEmergencyStop) {
		t.Fatalf("expected stderr build line to trip ErrEmergencyStop, got %v", res.Err)
	}
}

// generated host identity carries the per-run host comment and never the
// transport label.
func TestGeneratedVMIdentityCarriesPerRunComment(t *testing.T) {
	privateKey := filepath.Join(t.TempDir(), "ssh_host_ed25519_key")
	h := &Harness{runner: ExecRunner{}}
	if err := h.generateVMIdentityKey(context.Background(), privateKey); err != nil {
		t.Fatal(err)
	}
	pub, err := os.ReadFile(privateKey + ".pub")
	if err != nil {
		t.Fatal(err)
	}
	fields := strings.Fields(string(pub))
	if len(fields) < 3 {
		t.Fatalf("generated public key has no comment: %q", pub)
	}
	comment := strings.Join(fields[2:], " ")
	if comment != vmIdentityComment {
		t.Fatalf("generated identity comment %q", comment)
	}
	if strings.Contains(comment, "skadi-vm-test") {
		t.Fatalf("generated identity retained transport label %q", comment)
	}
}

// firstTwoFields extracts algo+blob from a stdout-only pubkey line, ignoring a
// trailing comment and surrounding whitespace (the assertGuestIdentity parse).
func TestFirstTwoFields(t *testing.T) {
	cases := []struct{ in, want string }{
		{"ssh-ed25519 AAAAC3Nza comment here", "ssh-ed25519 AAAAC3Nza"},
		{"  ssh-ed25519   AAAAC3Nza  ", "ssh-ed25519 AAAAC3Nza"},
		{"onlyonefield", ""},
		{"", ""},
	}
	for _, c := range cases {
		if got := firstTwoFields(c.in); got != c.want {
			t.Fatalf("firstTwoFields(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}

// scanDiskoDevices must extract the whole-disk target from a disko
// destroy/format/mount script body (partitions like /dev/vda1 are not disk
// nodes) and dedupe repeats down to exactly [/dev/vda].
func TestScanDiskoDevicesFromScriptBody(t *testing.T) {
	script := strings.Join([]string{
		"#!/usr/bin/env bash",
		"# disko destroy,format,mount for host vm",
		"sgdisk --zap-all /dev/vda",
		"wipefs --all --force /dev/vda",
		"partprobe /dev/vda",
		"mkfs.fat -F 32 /dev/vda1",
		"mkfs.ext4 -L nixos /dev/vda2",
		"mount /dev/vda2 /mnt",
	}, "\n")
	devs := scanDiskoDevices(script)
	if len(devs) != 1 || devs[0] != "/dev/vda" {
		t.Fatalf("scanDiskoDevices = %v, want [/dev/vda]", devs)
	}
}

// If the script ever referenced a second whole disk the scan must surface it, so
// the probe's exactly-[/dev/vda] assertion fails closed instead of wiping extra.
func TestScanDiskoDevicesFlagsSecondDisk(t *testing.T) {
	script := "wipefs --all /dev/vda\ndd if=/dev/zero of=/dev/vdb bs=1M count=1\n"
	devs := scanDiskoDevices(script)
	if len(devs) != 2 || devs[0] != "/dev/vda" || devs[1] != "/dev/vdb" {
		t.Fatalf("scanDiskoDevices = %v, want [/dev/vda /dev/vdb]", devs)
	}
}

// diskoScriptPath isolates the generated script path from dry-run stdout: the
// lone store-path line past warnings, or the disko-named one among deps; zero or
// ambiguous candidates fail closed.
func TestDiskoScriptPath(t *testing.T) {
	const diskoScript = "/nix/store/abcd1234abcd1234abcd1234abcd1234-disko-destroy-format-mount-vm"
	sole := "warning: Git tree '/tmp/skadi-install' is dirty\n" + diskoScript + "\n"
	if got, err := diskoScriptPath(sole); err != nil || got != diskoScript {
		t.Fatalf("diskoScriptPath(sole) = %q, %v; want %q, nil", got, err, diskoScript)
	}
	withDeps := "/nix/store/1111111111111111111111111111111a-bash-5.2\n" + diskoScript + "\n"
	if got, err := diskoScriptPath(withDeps); err != nil || got != diskoScript {
		t.Fatalf("diskoScriptPath(withDeps) = %q, %v; want %q, nil", got, err, diskoScript)
	}
	if _, err := diskoScriptPath("warning: nothing here\n"); err == nil {
		t.Fatal("expected diskoScriptPath to fail closed with no store path")
	}
	ambiguous := diskoScript + "\n/nix/store/eeee2222eeee2222eeee2222eeee2222-disko-mount\n"
	if _, err := diskoScriptPath(ambiguous); err == nil {
		t.Fatal("expected diskoScriptPath to fail closed on ambiguous disko paths")
	}
}

func TestInstallerTargetParseAndDrvComparison(t *testing.T) {
	want := "/nix/store/11111111111111111111111111111111-nixos-system-vm.drv"
	stdout := strings.Join([]string{
		"[skadi-install] using pre-staged pinned source",
		"resolved: skadi-install vm",
		"drvPath: " + want,
	}, "\n")
	got, err := parseInstallerTarget(stdout)
	if err != nil || !SameDrv(want, got) {
		t.Fatalf("parse installer target got=%q err=%v", got, err)
	}
	if SameDrv(want, "/nix/store/22222222222222222222222222222222-other.drv") {
		t.Fatal("drv mismatch passed")
	}
	if _, err := parseInstallerTarget("resolved: skadi-install vm\n"); err == nil {
		t.Fatal("missing labeled drvPath passed")
	}
	if _, err := parseInstallerTarget("drvPath: " + want + "\ndrvPath: " + gateDrv + "\n"); err == nil {
		t.Fatal("duplicate labeled drvPaths passed")
	}
}

func TestPrepareSourceFailureLeavesMeasurementsUnobserved(t *testing.T) {
	h := testHarness(t, fakeRunner{responder: func(CmdSpec) ([]string, int) { return nil, 0 }})
	if err := h.stagePrepareSource(context.Background()); err == nil {
		t.Fatal("prepare-source unexpectedly passed without resolve-rev")
	}
	if h.manifest.GateBuildCount != nil || h.manifest.GateFetchCount != nil || h.manifest.ProvisionBuildCount != nil {
		t.Fatalf("failed prepare-source invented measurements: %+v", h.manifest)
	}
	if strings.Contains(h.manifest.Human(), "build count") || strings.Contains(h.manifest.Human(), "fetch count") {
		t.Fatal("failed prepare-source report invented counts")
	}
}

func TestProvisionCountDoesNotClobberGateCounts(t *testing.T) {
	h := testHarness(t, nil)
	h.manifest.GateBuildCount = intPtr(0)
	h.manifest.GateFetchCount = intPtr(23)
	h.recordProvisionBuildCount(BuildPlan{WillBuild: []string{"/nix/store/x.drv"}})
	if *h.manifest.GateBuildCount != 0 || *h.manifest.GateFetchCount != 23 {
		t.Fatalf("gate counts changed: builds=%d fetches=%d", *h.manifest.GateBuildCount, *h.manifest.GateFetchCount)
	}
	if h.manifest.ProvisionBuildCount == nil || *h.manifest.ProvisionBuildCount != 1 {
		t.Fatalf("provision count = %v", h.manifest.ProvisionBuildCount)
	}
	human := h.manifest.Human()
	for _, label := range []string{"gate build count: 0", "gate fetch count: 23", "provision build count: 1"} {
		if !strings.Contains(human, label) {
			t.Fatalf("report missing %q:\n%s", label, human)
		}
	}
}

func TestSubstitutionCompletenessCommandsAndSuccessCleanup(t *testing.T) {
	h := testHarness(t, nil)
	if err := os.MkdirAll(h.cfg.EvidenceDir, 0o755); err != nil {
		t.Fatal(err)
	}
	h.cfg.TrustedPublicKey = h.cache.KeyName() + ":dGVzdA=="
	h.manifest.StorePaths = map[string]string{"toplevel": gateOutPath, "disko": gateDiskoOut}
	root := filepath.Join(h.cfg.EvidenceDir, "realization-store")
	wantCopy := []string{
		"copy",
		"--from", "file://" + h.cfg.CacheDir,
		"--to", "local?root=" + root,
		"--option", "trusted-public-keys", h.cfg.TrustedPublicKey,
		"--option", "require-sigs", "true",
		gateOutPath,
		gateDiskoOut,
	}
	wantBuild := []string{
		"build", "--no-link",
		"--store", "local?root=" + root,
		"--option", "substituters", "file://" + h.cfg.CacheDir,
		"--option", "trusted-public-keys", h.cfg.TrustedPublicKey,
		"--option", "require-sigs", "true",
		"--option", "always-allow-substitutes", "true",
		"--option", "max-jobs", "0",
		"--option", "builders", "",
		gateOutPath,
		gateDiskoOut,
	}
	inventoryCalls := 0
	h.runner = fakeRunner{responder: func(spec CmdSpec) ([]string, int) {
		if len(spec.Args) > 0 && spec.Args[0] == "copy" {
			if strings.Join(spec.Args, "\x00") != strings.Join(wantCopy, "\x00") {
				t.Fatalf("realization copy command %q", spec.Args)
			}
			return []string{
				"copying 3 paths...",
				"copying path '" + gateDep + "' from 'file://cache'...",
				"copying path '" + gateOutPath + "' from 'file://cache'...",
				"copying path '" + gateDiskoOut + "' from 'file://cache'...",
			}, 0
		}
		if len(spec.Args) > 0 && spec.Args[0] == "build" {
			if strings.Join(spec.Args, "\x00") != strings.Join(wantBuild, "\x00") {
				t.Fatalf("realization build command %q", spec.Args)
			}
			return nil, 0
		}
		if slicesContain(spec.Args, "--all") {
			inventoryCalls++
			if inventoryCalls == 1 {
				return []string{"[]"}, 0
			}
			return []string{fmt.Sprintf(`[{"path":%q},{"path":%q},{"path":%q}]`, gateOutPath, gateDiskoOut, gateDep)}, 0
		}
		if len(spec.Args) > 0 && spec.Args[0] == "path-info" {
			return []string{spec.Args[len(spec.Args)-1]}, 0
		}
		return nil, 1
	}}
	if err := h.stageSubstitutionCompletenessGate(context.Background()); err != nil {
		t.Fatal(err)
	}
	if inventoryCalls != 2 {
		t.Fatalf("inventory calls = %d, want measured before and after", inventoryCalls)
	}
	if h.manifest.RealizationBeforePaths == nil || *h.manifest.RealizationBeforePaths != 0 || h.manifest.RealizationAfterPaths == nil || *h.manifest.RealizationAfterPaths != 3 {
		t.Fatalf("path counts before=%v after=%v", h.manifest.RealizationBeforePaths, h.manifest.RealizationAfterPaths)
	}
	if h.manifest.GateBuildCount == nil || *h.manifest.GateBuildCount != 0 || h.manifest.GateFetchCount == nil || *h.manifest.GateFetchCount != 3 {
		t.Fatalf("gate counts builds=%v fetches=%v", h.manifest.GateBuildCount, h.manifest.GateFetchCount)
	}
	if _, err := os.Stat(root); !os.IsNotExist(err) {
		t.Fatalf("successful realization store retained: %v", err)
	}
}

func TestSubstitutionCompletenessFailsClosedWhenBeforeInventoryCannotInitialize(t *testing.T) {
	h := testHarness(t, nil)
	if err := os.MkdirAll(h.cfg.EvidenceDir, 0o755); err != nil {
		t.Fatal(err)
	}
	h.cfg.TrustedPublicKey = h.cache.KeyName() + ":dGVzdA=="
	h.manifest.StorePaths = map[string]string{"toplevel": gateOutPath, "disko": gateDiskoOut}
	copyCalled := false
	h.runner = fakeRunner{responder: func(spec CmdSpec) ([]string, int) {
		if slicesContain(spec.Args, "--all") {
			return []string{"error: cannot initialize local store"}, 1
		}
		if len(spec.Args) > 0 && spec.Args[0] == "copy" {
			copyCalled = true
		}
		return nil, 1
	}}
	if err := h.stageSubstitutionCompletenessGate(context.Background()); err == nil || !strings.Contains(err.Error(), "inventory pre-copy realization store") {
		t.Fatalf("uninitializable before inventory did not fail closed: %v", err)
	}
	if copyCalled {
		t.Fatal("copy ran after the before inventory failed")
	}
	if h.manifest.RealizationBeforePaths != nil {
		t.Fatalf("failed inventory invented a before count: %v", h.manifest.RealizationBeforePaths)
	}
}

func TestRemoveIsolatedStoreRootHandlesReadOnlyPaths(t *testing.T) {
	root := filepath.Join(t.TempDir(), "isolated-store")
	nested := filepath.Join(root, "nix", "store", "readonly", "share", "man")
	if err := os.MkdirAll(nested, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(nested, "page.1.gz"), []byte("manual"), 0o444); err != nil {
		t.Fatal(err)
	}
	for _, dir := range []string{nested, filepath.Dir(nested), filepath.Dir(filepath.Dir(nested))} {
		if err := os.Chmod(dir, 0o555); err != nil {
			t.Fatal(err)
		}
	}
	if err := removeIsolatedStoreRoot(root); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(root); !os.IsNotExist(err) {
		t.Fatalf("read-only isolated store retained: %v", err)
	}
}

func TestSubstitutionCompletenessBuildLineStopsAndRetainsStore(t *testing.T) {
	h := testHarness(t, nil)
	if err := os.MkdirAll(h.cfg.EvidenceDir, 0o755); err != nil {
		t.Fatal(err)
	}
	h.cfg.TrustedPublicKey = h.cache.KeyName() + ":dGVzdA=="
	h.manifest.StorePaths = map[string]string{"toplevel": gateOutPath, "disko": gateDiskoOut}
	h.runner = fakeRunner{responder: func(spec CmdSpec) ([]string, int) {
		if slicesContain(spec.Args, "--all") {
			return []string{"[]"}, 0
		}
		if len(spec.Args) > 0 && spec.Args[0] == "copy" {
			return []string{
				"copying 3 paths...",
				"copying path '" + gateDep + "' from 'file://cache'...",
				"copying path '" + gateOutPath + "' from 'file://cache'...",
				"copying path '" + gateDiskoOut + "' from 'file://cache'...",
			}, 0
		}
		if len(spec.Args) > 0 && spec.Args[0] == "build" {
			return strings.Split(strings.TrimSpace(readFixture(t, "failed_will_be_built.log")), "\n"), 1
		}
		return nil, 1
	}}
	err := h.stageSubstitutionCompletenessGate(context.Background())
	if !errors.Is(err, ErrEmergencyStop) {
		t.Fatalf("expected emergency stop, got %v", err)
	}
	if h.manifest.GateBuildCount != nil {
		t.Fatalf("emergency stop published a truncated build count: %v", h.manifest.GateBuildCount)
	}
	if !strings.Contains(err.Error(), "build announced") {
		t.Fatalf("emergency stop omitted the observed announcement: %v", err)
	}
	if _, err := os.Stat(filepath.Join(h.cfg.EvidenceDir, "realization-store")); err != nil {
		t.Fatalf("failed realization store was not retained: %v", err)
	}
}

func TestSubstitutionCompletenessWithheldPathAnnouncesBuildAndFailsClosed(t *testing.T) {
	h := testHarness(t, nil)
	if err := os.MkdirAll(h.cfg.EvidenceDir, 0o755); err != nil {
		t.Fatal(err)
	}
	h.cfg.TrustedPublicKey = h.cache.KeyName() + ":dGVzdA=="
	h.manifest.StorePaths = map[string]string{"toplevel": gateOutPath, "disko": gateDiskoOut}
	h.runner = fakeRunner{responder: func(spec CmdSpec) ([]string, int) {
		if slicesContain(spec.Args, "--all") {
			return []string{"[]"}, 0
		}
		if len(spec.Args) > 0 && spec.Args[0] == "copy" {
			return []string{
				"copying 2 paths...",
				"copying path '" + gateDep + "' from 'file://cache'...",
				"copying path '" + gateOutPath + "' from 'file://cache'...",
			}, 0
		}
		if len(spec.Args) > 0 && spec.Args[0] == "build" {
			return []string{
				"this derivation will be built:",
				"  " + gateDiskoDrv,
				"building '" + gateDiskoDrv + "'...",
			}, 1
		}
		return nil, 1
	}}
	err := h.stageSubstitutionCompletenessGate(context.Background())
	if !errors.Is(err, ErrEmergencyStop) {
		t.Fatalf("withheld disko path did not fail closed on announced work: %v", err)
	}
	if h.manifest.GateFetchCount == nil || *h.manifest.GateFetchCount != 2 {
		t.Fatalf("withheld-copy fetch count = %v", h.manifest.GateFetchCount)
	}
	if h.manifest.GateBuildCount != nil {
		t.Fatalf("withheld-path emergency published a truncated build count: %v", h.manifest.GateBuildCount)
	}
	if !strings.Contains(err.Error(), "build announced") {
		t.Fatalf("withheld-path failure omitted the observed announcement: %v", err)
	}
}

func TestSubstitutionCompletenessNonEmergencyFailureOmitsBuildCount(t *testing.T) {
	h := testHarness(t, nil)
	if err := os.MkdirAll(h.cfg.EvidenceDir, 0o755); err != nil {
		t.Fatal(err)
	}
	h.cfg.TrustedPublicKey = h.cache.KeyName() + ":dGVzdA=="
	h.manifest.StorePaths = map[string]string{"toplevel": gateOutPath, "disko": gateDiskoOut}
	h.runner = fakeRunner{responder: func(spec CmdSpec) ([]string, int) {
		if slicesContain(spec.Args, "--all") {
			return []string{"[]"}, 0
		}
		if len(spec.Args) > 0 && spec.Args[0] == "copy" {
			return []string{
				"copying 3 paths...",
				"copying path '" + gateDep + "' from 'file://cache'...",
				"copying path '" + gateOutPath + "' from 'file://cache'...",
				"copying path '" + gateDiskoOut + "' from 'file://cache'...",
			}, 0
		}
		if len(spec.Args) > 0 && spec.Args[0] == "build" {
			return []string{"error: signature rejected"}, 1
		}
		return nil, 1
	}}
	err := h.stageSubstitutionCompletenessGate(context.Background())
	if err == nil || !strings.Contains(err.Error(), "realization failed") {
		t.Fatalf("non-emergency build failure did not fail closed: %v", err)
	}
	if h.manifest.GateBuildCount != nil {
		t.Fatalf("failed build published a passing-looking count: %v", h.manifest.GateBuildCount)
	}
	if h.manifest.GateFetchCount == nil || *h.manifest.GateFetchCount != 3 {
		t.Fatalf("completed copy measurement was lost: %v", h.manifest.GateFetchCount)
	}
}

func TestSubstitutionCompletenessMissingOutPathFailsClosed(t *testing.T) {
	h := testHarness(t, nil)
	if err := os.MkdirAll(h.cfg.EvidenceDir, 0o755); err != nil {
		t.Fatal(err)
	}
	h.cfg.TrustedPublicKey = h.cache.KeyName() + ":dGVzdA=="
	h.manifest.StorePaths = map[string]string{"toplevel": gateOutPath, "disko": gateDiskoOut}
	h.runner = fakeRunner{responder: func(spec CmdSpec) ([]string, int) {
		if slicesContain(spec.Args, "--all") {
			return []string{"[]"}, 0
		}
		if len(spec.Args) > 0 && spec.Args[0] == "copy" {
			return []string{
				"copying 3 paths...",
				"copying path '" + gateDep + "' from 'file://cache'...",
				"copying path '" + gateOutPath + "' from 'file://cache'...",
				"copying path '" + gateDiskoOut + "' from 'file://cache'...",
			}, 0
		}
		if len(spec.Args) > 0 && spec.Args[0] == "build" {
			return nil, 0
		}
		if len(spec.Args) > 0 && spec.Args[0] == "path-info" {
			if spec.Args[len(spec.Args)-1] == gateDiskoOut {
				return []string{"missing"}, 1
			}
			return []string{gateOutPath}, 0
		}
		return nil, 1
	}}
	if err := h.stageSubstitutionCompletenessGate(context.Background()); err == nil || !strings.Contains(err.Error(), "missing required out path") {
		t.Fatalf("missing out path did not fail closed: %v", err)
	}
}

func TestGuestProofParsersFailClosed(t *testing.T) {
	if state, err := parseUnitState("active\n"); err != nil || state != "active" {
		t.Fatalf("unit state got=%q err=%v", state, err)
	}
	for _, malformed := range []string{"", "active\nfailed\n"} {
		if _, err := parseUnitState(malformed); err == nil {
			t.Fatalf("malformed unit state passed: %q", malformed)
		}
	}
	if err := parseQemuImgCheck("No errors were found on the image.\n"); err != nil {
		t.Fatal(err)
	}
	if err := parseQemuImgCheck("ERROR refcount mismatch"); err == nil {
		t.Fatal("bad qcow2 check passed")
	}
	if err := validatePoweroffOutcome(255, true, 0, nil); err != nil {
		t.Fatal(err)
	}
	if err := validatePoweroffOutcome(0, false, 0, nil); err == nil {
		t.Fatal("poweroff timeout passed")
	}
}

func slicesContain(values []string, want string) bool {
	for _, value := range values {
		if value == want {
			return true
		}
	}
	return false
}

func TestReusePreparedSourcePinsCacheInput(t *testing.T) {
	ctx := context.Background()
	source := t.TempDir()
	runGit := func(args ...string) string {
		t.Helper()
		res := ExecRunner{}.Run(ctx, CmdSpec{Name: "git", Args: args, Dir: source}, nil)
		if res.Err != nil || res.ExitCode != 0 {
			t.Fatalf("git %s exit=%d err=%v\n%s", strings.Join(args, " "), res.ExitCode, res.Err, res.Combined)
		}
		return strings.TrimSpace(res.Stdout)
	}
	runGit("init", "--quiet")
	runGit("config", "user.name", "Harness Test")
	runGit("config", "user.email", "harness-test@example.invalid")
	if err := os.WriteFile(filepath.Join(source, "base"), []byte("base\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	runGit("add", "base")
	runGit("commit", "--quiet", "-m", "base")
	rev := runGit("rev-parse", "HEAD")
	fixture := filepath.Join(source, vmFixtureRelPath)
	if err := os.MkdirAll(filepath.Dir(fixture), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(fixture, []byte("sops: encrypted fixture\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	runGit("add", vmFixtureRelPath)

	h := testHarness(t, ExecRunner{})
	h.cfg.Subcommand = "gate"
	h.cfg.PreparedSource = source
	h.manifest.Rev = rev
	if err := h.stageReusePreparedSource(ctx); err != nil {
		t.Fatal(err)
	}
	if h.preparedSource != source {
		t.Fatalf("prepared source = %q, want %q", h.preparedSource, source)
	}
	if h.vmIdentity != nil {
		t.Fatal("cache-source reuse invented a new vm identity")
	}
	if h.manifest.VMFixtureSHA256 == "" || h.manifest.PreparedSourceHash == "" {
		t.Fatalf("reused source proof is incomplete: %+v", h.manifest)
	}
	if h.manifest.PreparedSourceReused == nil || !*h.manifest.PreparedSourceReused || h.manifest.PreparedSourceOrigin != filepath.Dir(source) {
		t.Fatalf("reused source provenance is incomplete: %+v", h.manifest)
	}
	for _, want := range []string{"prepared reused: true", "prepared origin run: " + filepath.Dir(source)} {
		if !strings.Contains(h.manifest.Human(), want) {
			t.Fatalf("human report omitted %q:\n%s", want, h.manifest.Human())
		}
	}
}

func TestReusePreparedSourceRejectsProvision(t *testing.T) {
	h := testHarness(t, nil)
	h.cfg.Subcommand = "provision"
	if err := h.stageReusePreparedSource(context.Background()); err == nil {
		t.Fatal("provision accepted a reused gate-only prepared source")
	}
}
