package harness

import (
	"context"
	"errors"
	"fmt"
	"io"
	"log"
	"strings"
	"testing"
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

// The build-plan gate is a signed cache-closure proof: `nix derivation show`
// yields the toplevel out path, then `nix path-info --store file://<cache>
// --recursive --sigs --json` must return a complete closure whose every path is
// signed by the per-rev key. These fakeRunner tests cover pass / incomplete /
// untrusted-signature without invoking nix.
const (
	gateDrv     = "/nix/store/dddd0000dddd0000dddd0000dddd0000-nixos-system-vm.drv"
	gateOutPath = "/nix/store/qr05v34zqr05v34zqr05v34zqr05v34z-nixos-system-vm-26.05"
	gateDep     = "/nix/store/aaaa1111aaaa1111aaaa1111aaaa1111-glibc-2.39"
)

// gateRunner answers `nix derivation show` with gateOutPath and `nix path-info`
// with the supplied JSON body and exit code.
func gateRunner(pathInfoJSON string, pathInfoExit int) fakeRunner {
	return fakeRunner{responder: func(spec CmdSpec) ([]string, int) {
		if len(spec.Args) > 0 && spec.Args[0] == "derivation" {
			return []string{fmt.Sprintf(`{%q:{"outputs":{"out":{"path":%q}}}}`, gateDrv, gateOutPath)}, 0
		}
		if len(spec.Args) > 0 && spec.Args[0] == "path-info" {
			return []string{pathInfoJSON}, pathInfoExit
		}
		return nil, 0
	}}
}

// (i) A complete closure, every path signed by the per-rev key, passes with 0
// builds and a fetch count equal to the closure size.
func TestBuildPlanGatePassesFullySignedClosure(t *testing.T) {
	h := testHarness(t, nil)
	key := h.cache.KeyName()
	body := fmt.Sprintf(`[{"path":%q,"signatures":[%q]},{"path":%q,"signatures":[%q]}]`,
		gateOutPath, key+":sigA==", gateDep, key+":sigB==")
	h.runner = gateRunner(body, 0)
	h.manifest.DrvPaths = map[string]string{"toplevel": gateDrv}
	if err := h.stageBuildPlanGate(context.Background()); err != nil {
		t.Fatalf("expected a fully-signed closure to pass, got %v", err)
	}
	if h.manifest.LiveBuildCount != 0 {
		t.Fatalf("expected build count 0, got %d", h.manifest.LiveBuildCount)
	}
	if h.manifest.FetchCount != 2 {
		t.Fatalf("expected fetch count 2 (closure size), got %d", h.manifest.FetchCount)
	}
}

// (ii) path-info exits nonzero when a referenced path is missing from the signed
// cache; the gate must fail closed.
func TestBuildPlanGateFailsMissingClosurePath(t *testing.T) {
	h := testHarness(t, nil)
	h.runner = gateRunner(`error: path '/nix/store/missing' is not valid`, 1)
	h.manifest.DrvPaths = map[string]string{"toplevel": gateDrv}
	if err := h.stageBuildPlanGate(context.Background()); err == nil {
		t.Fatal("expected gate to fail closed when the cached closure is incomplete")
	}
}

// (iii) A closure path signed only by a non-trusted (golden) key must fail
// closed.
func TestBuildPlanGateFailsUntrustedSignature(t *testing.T) {
	h := testHarness(t, nil)
	key := h.cache.KeyName()
	body := fmt.Sprintf(`[{"path":%q,"signatures":[%q]},{"path":%q,"signatures":[%q]}]`,
		gateOutPath, key+":sigA==", gateDep, "skadi-golden-cafebabe:sigX==")
	h.runner = gateRunner(body, 0)
	h.manifest.DrvPaths = map[string]string{"toplevel": gateDrv}
	if err := h.stageBuildPlanGate(context.Background()); err == nil {
		t.Fatal("expected gate to fail closed on an untrusted signature")
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
	runner := fakeRunner{responder: func(spec CmdSpec) ([]string, int) {
		return []string{want}, 0
	}}
	h := testHarness(t, runner)
	if err := h.stageEvalDrv(context.Background()); err != nil {
		t.Fatalf("expected clean stdout drv to be accepted, got %v", err)
	}
	if got := h.manifest.DrvPaths["toplevel"]; got != want {
		t.Fatalf("stored drv = %q, want %q", got, want)
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
