package harness

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

// Config parameterizes a single rebuild run.
type Config struct {
	Rev         string
	Host        string
	StateDir    string
	EvidenceDir string
	CacheDir    string
	Port        int
	RAM         int
	Cores       int
	Disk        string
	Subcommand  string // check | build-cache | gate | provision | all
	Confirm     ConfirmFunc
}

// ConfirmFunc prompts a human and returns their typed response.
type ConfirmFunc func(prompt string) (string, error)

// Harness drives the fail-closed rebuild state machine.
type Harness struct {
	cfg        Config
	runner     Runner
	log        *log.Logger
	cache      *Cache
	server     *FileServer
	manifest   *Manifest
	signingKey SigningKey
	repoRoot   string
	guest      *Guest
	goldenDir  string
}

// New builds a Harness. A nil logger logs to stderr.
func New(cfg Config, runner Runner, logger *log.Logger) *Harness {
	if logger == nil {
		logger = log.New(os.Stderr, "rebuild-vm-golden ", log.LstdFlags)
	}
	return &Harness{
		cfg:    cfg,
		runner: runner,
		log:    logger,
		cache: &Cache{
			Dir:         cfg.CacheDir,
			EvidenceDir: cfg.EvidenceDir,
			Rev:         cfg.Rev,
			Runner:      runner,
		},
		manifest: &Manifest{
			Rev:        cfg.Rev,
			Subcommand: cfg.Subcommand,
			Host:       cfg.Host,
			StartedAt:  time.Now().UTC(),
		},
	}
}

type stage struct {
	name        string
	destructive bool
	fn          func(ctx context.Context) error
}

func (h *Harness) allStages() []stage {
	// Order matters: build+sign the cache before cache-check/build-plan-gate validate
	// it; serve-cache (guest HTTP) is unused by the gate so it sits before the guest stages.
	return []stage{
		{name: "preflight", fn: h.stagePreflight},
		{name: "resolve-rev", fn: h.stageResolveRev},
		{name: "eval-drv", fn: h.stageEvalDrv},
		{name: "signing-key", fn: h.stageSigningKey},
		{name: "export-sign", fn: h.stageExportSign},
		{name: "cache-check", fn: h.stageCacheCheck},
		{name: "build-plan-gate", fn: h.stageBuildPlanGate},
		{name: "serve-cache", fn: h.stageServeCache},
		{name: "guest-launch", fn: h.stageGuestLaunch},
		{name: "negative-wipe-probe", fn: h.stageNegativeWipeProbe},
		{name: "confirm-gate", destructive: true, fn: h.stageConfirmGate},
		{name: "guest-provision", destructive: true, fn: h.stageGuestProvision},
		{name: "first-boot-proof", fn: h.stageFirstBootProof},
		{name: "freeze", fn: h.stageFreeze},
		{name: "overlay-proof", fn: h.stageOverlayProof},
		{name: "finalize", fn: h.stageFinalize},
	}
}

func (h *Harness) stagesFor(sub string) ([]stage, error) {
	all := h.allStages()
	byName := make(map[string]stage, len(all))
	for _, s := range all {
		byName[s.name] = s
	}
	var names []string
	switch sub {
	case "check":
		names = []string{"preflight", "resolve-rev", "eval-drv", "cache-check"}
	case "gate":
		names = []string{"preflight", "resolve-rev", "eval-drv", "cache-check", "build-plan-gate"}
	case "build-cache":
		names = []string{"preflight", "resolve-rev", "eval-drv", "signing-key", "export-sign", "serve-cache"}
	case "provision":
		names = []string{"preflight", "resolve-rev", "eval-drv", "signing-key", "export-sign", "cache-check", "build-plan-gate", "serve-cache", "guest-launch", "negative-wipe-probe", "confirm-gate", "guest-provision", "first-boot-proof"}
	case "all":
		for _, s := range all {
			names = append(names, s.name)
		}
	default:
		return nil, fmt.Errorf("unknown subcommand %q (want check|build-cache|gate|provision|all)", sub)
	}
	out := make([]stage, 0, len(names))
	for _, n := range names {
		out = append(out, byName[n])
	}
	return out, nil
}

// Run executes the stages selected by the subcommand, fail-closed. teardown and
// the report write always run via defer.
func (h *Harness) Run(ctx context.Context) (*Manifest, error) {
	defer h.teardown()
	defer h.writeReport()

	stages, err := h.stagesFor(h.cfg.Subcommand)
	if err != nil {
		h.finish("invalid", "dispatch")
		return h.manifest, err
	}

	last := "dispatch"
	for _, st := range stages {
		if cerr := ctx.Err(); cerr != nil {
			h.finish("aborted", last)
			return h.manifest, fmt.Errorf("aborted before stage %s: %w", st.name, cerr)
		}
		if st.destructive {
			h.log.Printf("stage %s: DESTRUCTIVE", st.name)
		}
		start := time.Now()
		h.log.Printf("stage %s: start", st.name)
		serr := st.fn(ctx)
		rec := StageRecord{Name: st.name, Elapsed: time.Since(start)}
		if serr != nil {
			rec.Status = "failed"
			rec.Err = serr.Error()
			h.manifest.Stages = append(h.manifest.Stages, rec)
			h.finish("failed", st.name)
			h.log.Printf("stage %s: FAILED: %v", st.name, serr)
			return h.manifest, fmt.Errorf("stage %s: %w", st.name, serr)
		}
		rec.Status = "pass"
		h.manifest.Stages = append(h.manifest.Stages, rec)
		last = st.name
		h.log.Printf("stage %s: pass (%s)", st.name, rec.Elapsed.Round(time.Millisecond))
	}
	h.finish("complete", last)
	return h.manifest, nil
}

func (h *Harness) finish(status, finalStage string) {
	h.manifest.Status = status
	h.manifest.FinalStage = finalStage
	h.manifest.FinishedAt = time.Now().UTC()
}

func (h *Harness) teardown() {
	if h.guest != nil {
		h.guest.stop()
		h.guest = nil
	}
	if h.server != nil {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = h.server.Close(ctx)
		h.server = nil
	}
}

func (h *Harness) writeReport() {
	dir := h.cfg.EvidenceDir
	if dir == "" {
		dir = h.cfg.StateDir
	}
	if dir == "" {
		return
	}
	if err := os.MkdirAll(dir, 0o755); err != nil {
		h.log.Printf("write report: %v", err)
		return
	}
	if err := h.manifest.WriteJSON(filepath.Join(dir, "report.json")); err != nil {
		h.log.Printf("write report json: %v", err)
	}
	if err := h.manifest.WriteHuman(filepath.Join(dir, "report.txt")); err != nil {
		h.log.Printf("write report txt: %v", err)
	}
}

// --- stages ---

func (h *Harness) stagePreflight(ctx context.Context) error {
	_ = ctx
	if strings.TrimSpace(h.cfg.Rev) == "" {
		return fmt.Errorf("rev is required")
	}
	if h.cfg.StateDir == "" {
		return fmt.Errorf("state-dir is required")
	}
	for _, d := range []string{h.cfg.StateDir, h.cfg.EvidenceDir, h.cfg.CacheDir} {
		if d == "" {
			continue
		}
		if err := os.MkdirAll(d, 0o755); err != nil {
			return fmt.Errorf("create dir %s: %w", d, err)
		}
	}
	return nil
}

func (h *Harness) stageResolveRev(ctx context.Context) error {
	res := h.runner.Run(ctx, CmdSpec{Name: "git", Args: []string{"rev-parse", "--verify", h.cfg.Rev + "^{commit}"}}, nil)
	if res.Err != nil || res.ExitCode != 0 {
		return fmt.Errorf("resolve rev %q (exit %d): %w\n%s", h.cfg.Rev, res.ExitCode, res.Err, res.Combined)
	}
	if full := strings.TrimSpace(res.Stdout); full != "" {
		h.manifest.Rev = full
		h.cache.Rev = full
	}
	// Resolve the repo root so eval/build can be pinned to the exact committed
	// rev (git+file://<root>?rev=<full>#…) rather than the dirty working tree.
	top := h.runner.Run(ctx, CmdSpec{Name: "git", Args: []string{"rev-parse", "--show-toplevel"}}, nil)
	if top.Err != nil || top.ExitCode != 0 {
		return fmt.Errorf("resolve repo root (exit %d): %w\n%s", top.ExitCode, top.Err, top.Combined)
	}
	h.repoRoot = strings.TrimSpace(top.Stdout)
	return nil
}

func (h *Harness) stageEvalDrv(ctx context.Context) error {
	if h.manifest.DrvPaths == nil {
		h.manifest.DrvPaths = map[string]string{}
	}
	attr := fmt.Sprintf("nixosConfigurations.%s.config.system.build.toplevel.drvPath", h.cfg.Host)
	res := h.runner.Run(ctx, CmdSpec{Name: "nix", Args: []string{"eval", "--raw", h.flakeRef(attr)}}, nil)
	if res.Err != nil || res.ExitCode != 0 {
		return fmt.Errorf("eval toplevel drvPath (exit %d): %w\n%s", res.ExitCode, res.Err, res.Combined)
	}
	// Parse stdout only: nix logs "fetching git input"/"saved setting" to stderr, and a
	// poisoned drvPath would silently break export-sign; require exactly one .drv.
	drv, err := singleStorePath(res.Stdout, ".drv")
	if err != nil {
		return fmt.Errorf("eval toplevel drvPath: %w\nstdout: %q\ncombined:\n%s", err, res.Stdout, res.Combined)
	}
	h.manifest.DrvPaths["toplevel"] = drv
	return nil
}

func (h *Harness) stageCacheCheck(ctx context.Context) error {
	_ = ctx
	h.manifest.CacheKey = h.cache.CacheKey()
	inv, err := h.cache.Inventory()
	if err != nil {
		return err
	}
	if len(inv) == 0 {
		return fmt.Errorf("cache %s is empty; run build-cache first", h.cfg.CacheDir)
	}
	return nil
}

func (h *Harness) stageBuildPlanGate(ctx context.Context) error {
	drv := h.manifest.DrvPaths["toplevel"]
	if drv == "" {
		return fmt.Errorf("no toplevel drv resolved; eval-drv must run first")
	}
	// Resolve the toplevel OUTPUT path from the already-evaluated drv (no second
	// eval). Parse stdout only; stderr carries fetch/warning noise (as in eval-drv).
	show := h.runner.Run(ctx, CmdSpec{Name: "nix", Args: []string{"derivation", "show", drv}}, nil)
	if show.Err != nil || show.ExitCode != 0 {
		return fmt.Errorf("derivation show %s (exit %d): %w\n%s", drv, show.ExitCode, show.Err, show.Combined)
	}
	outPath, err := drvOutPath(show.Stdout, drv)
	if err != nil {
		return fmt.Errorf("resolve toplevel out path: %w\nstdout: %q\ncombined:\n%s", err, show.Stdout, show.Combined)
	}
	// Store-isolated BY CONSTRUCTION: --store file://<cache> consults only the
	// signed cache, so a complete, fully-signed runtime closure here proves the
	// toplevel is cached (0 builds) with no chroot store and no dry-run.
	store := "file://" + h.cfg.CacheDir
	pi := h.runner.Run(ctx, CmdSpec{Name: "nix", Args: []string{"path-info", "--store", store, "--recursive", "--sigs", "--json", outPath}}, nil)
	if pi.Err != nil || pi.ExitCode != 0 {
		return fmt.Errorf("gate not cached: closure of %s incomplete in signed cache %s (exit %d): %w\n%s", outPath, store, pi.ExitCode, pi.Err, pi.Combined)
	}
	closure, err := parsePathInfoSigs(pi.Stdout)
	if err != nil {
		return fmt.Errorf("parse cache closure: %w\nstdout: %q", err, pi.Stdout)
	}
	if len(closure) == 0 {
		return fmt.Errorf("gate vacuous: signed cache %s returned an empty closure for %s", store, outPath)
	}
	if _, ok := closure[outPath]; !ok {
		return fmt.Errorf("gate not cached: toplevel out %s absent from its own cached closure", outPath)
	}
	// Every closure path must be signed by the per-rev trusted key; this replaces
	// require-sigs + trusted-public-keys enforcement from the old dry-run gate.
	trusted := h.cache.KeyName()
	for p, sigs := range closure {
		if !signedByKey(sigs, trusted) {
			return fmt.Errorf("gate not cached: %s is not signed by trusted key %s", p, trusted)
		}
	}
	h.manifest.FetchCount = len(closure)
	h.manifest.LiveBuildCount = 0
	return nil
}

func (h *Harness) stageSigningKey(ctx context.Context) error {
	_ = ctx
	key, err := GenerateSigningKey(h.cfg.EvidenceDir, h.cache.KeyName())
	if err != nil {
		return err
	}
	h.signingKey = key
	h.manifest.PublicKey = key.Public
	return nil
}

func (h *Harness) stageExportSign(ctx context.Context) error {
	if err := h.cache.Ensure(); err != nil {
		return err
	}
	drv := h.manifest.DrvPaths["toplevel"]
	if drv == "" {
		return fmt.Errorf("no toplevel drv resolved; eval-drv must run first")
	}
	res := h.runner.Run(ctx, CmdSpec{Name: "nix", Args: []string{"build", "--no-link", "--print-out-paths", drv + "^*"}}, nil)
	if res.Err != nil || res.ExitCode != 0 {
		return fmt.Errorf("realize toplevel (exit %d): %w\n%s", res.ExitCode, res.Err, res.Combined)
	}
	// Parse stdout only and keep bare store paths; warnings/build logs go to stderr.
	paths := storePathLines(res.Stdout)
	if len(paths) == 0 {
		return fmt.Errorf("realize toplevel produced no store paths\nstdout: %q\ncombined:\n%s", res.Stdout, res.Combined)
	}
	if h.manifest.StorePaths == nil {
		h.manifest.StorePaths = map[string]string{}
	}
	h.manifest.StorePaths["toplevel"] = paths[0]
	if err := h.cache.Sign(ctx, h.signingKey, paths); err != nil {
		return err
	}
	return h.cache.Export(ctx, paths)
}

func (h *Harness) stageServeCache(ctx context.Context) error {
	_ = ctx
	if err := h.cache.Ensure(); err != nil {
		return err
	}
	srv, err := StartFileServer(h.cfg.CacheDir, h.cfg.Port)
	if err != nil {
		return err
	}
	h.server = srv
	h.log.Printf("serving cache %s at %s", h.cfg.CacheDir, srv.URL())
	return nil
}

func (h *Harness) stageConfirmGate(ctx context.Context) error {
	_ = ctx
	if h.cfg.Confirm == nil {
		return fmt.Errorf("destructive stage requires a confirmation function")
	}
	short := shortRev(h.manifest.Rev)
	prompt := fmt.Sprintf("About to WIPE and reinstall host %q at rev %s.\nProbed destructive target: /dev/vda (negative-wipe probe passed).\nType the rev short-hash %q to proceed: ", h.cfg.Host, h.manifest.Rev, short)
	got, err := h.cfg.Confirm(prompt)
	if err != nil {
		return fmt.Errorf("confirmation aborted: %w", err)
	}
	if strings.TrimSpace(got) != short {
		return fmt.Errorf("confirmation mismatch: got %q want %q", strings.TrimSpace(got), short)
	}
	return nil
}

func (h *Harness) stageFinalize(ctx context.Context) error {
	_ = ctx
	// Retention: the golden and every working/evidence dir are kept in place;
	// nothing is pruned here (pruning is a separate, explicit opt-in). The
	// install-log + first-boot serial hashes were recorded by the guest stages.
	if h.goldenDir != "" {
		h.manifest.GoldenDir = h.goldenDir
	}
	h.log.Printf("run complete for rev %s (golden: %s)", h.manifest.Rev, h.manifest.GoldenDir)
	return nil
}

// --- helpers ---

// flakeRef builds a flake reference pinned to the resolved commit so evaluation
// is deterministic and independent of the (possibly dirty) working tree. The
// rev must be committed for git+file to resolve it.
func (h *Harness) flakeRef(attr string) string {
	return fmt.Sprintf("git+file://%s?rev=%s#%s", h.repoRoot, h.manifest.Rev, attr)
}

func buildGateWatcher(onViolation func(string)) LineWatcher {
	return func(line string) error {
		if v := BuildLineViolation(line); v != "" {
			if onViolation != nil {
				onViolation(v)
			}
			return fmt.Errorf("%w: %s", ErrEmergencyStop, v)
		}
		return nil
	}
}

var reDiskNode = regexp.MustCompile(`/dev/(?:vd[a-z]|sd[a-z]|xvd[a-z]|nvme\d+n\d+)\b`)

func scanDiskoDevices(output string) []string {
	seen := map[string]bool{}
	var out []string
	for _, m := range reDiskNode.FindAllString(output, -1) {
		if seen[m] {
			continue
		}
		seen[m] = true
		out = append(out, m)
	}
	return out
}

func splitNonEmptyLines(s string) []string {
	var out []string
	for _, ln := range strings.Split(s, "\n") {
		if ln = strings.TrimSpace(ln); ln != "" {
			out = append(out, ln)
		}
	}
	return out
}

var reStorePath = regexp.MustCompile(`^/nix/store/\S+$`)

// singleStorePath returns the sole /nix/store path in s (a stdout-only capture),
// erroring unless there is exactly one; suffix, if set, must terminate it.
func singleStorePath(s, suffix string) (string, error) {
	lines := splitNonEmptyLines(s)
	if len(lines) != 1 {
		return "", fmt.Errorf("want exactly one /nix/store path, got %d line(s)", len(lines))
	}
	p := lines[0]
	if !reStorePath.MatchString(p) {
		return "", fmt.Errorf("not a /nix/store path: %q", p)
	}
	if suffix != "" && !strings.HasSuffix(p, suffix) {
		return "", fmt.Errorf("store path %q does not end in %q", p, suffix)
	}
	return p, nil
}

// storePathLines keeps only the bare /nix/store path lines of a stdout capture.
func storePathLines(s string) []string {
	var out []string
	for _, ln := range splitNonEmptyLines(s) {
		if reStorePath.MatchString(ln) {
			out = append(out, ln)
		}
	}
	return out
}

// drvOutPath parses `nix derivation show <drv>` stdout -- a JSON object keyed by
// derivation store path -- and returns the single "out" output path.
func drvOutPath(jsonStr, drv string) (string, error) {
	var m map[string]struct {
		Outputs map[string]struct {
			Path string `json:"path"`
		} `json:"outputs"`
	}
	if err := json.Unmarshal([]byte(strings.TrimSpace(jsonStr)), &m); err != nil {
		return "", fmt.Errorf("unmarshal derivation show json: %w", err)
	}
	entry, ok := m[drv]
	if !ok && len(m) == 1 {
		// Tolerate a lone entry whose key spelling differs from drv.
		for _, v := range m {
			entry, ok = v, true
		}
	}
	if !ok {
		return "", fmt.Errorf("derivation %s absent from `nix derivation show` output", drv)
	}
	out, ok := entry.Outputs["out"]
	if !ok {
		return "", fmt.Errorf("derivation %s has no \"out\" output", drv)
	}
	// Reuse the single-store-path discipline; an output has no .drv suffix.
	return singleStorePath(out.Path, "")
}

// parsePathInfoSigs parses `nix path-info --sigs --json` into store path ->
// signatures. Lix emits a JSON array (lix issue #1100); upstream Nix (>= ~2.14)
// emits an object keyed by store path. Both shapes are accepted.
func parsePathInfoSigs(jsonStr string) (map[string][]string, error) {
	s := strings.TrimSpace(jsonStr)
	out := map[string][]string{}
	if s == "" {
		return out, nil
	}
	switch s[0] {
	case '[':
		var arr []struct {
			Path       string   `json:"path"`
			Signatures []string `json:"signatures"`
		}
		if err := json.Unmarshal([]byte(s), &arr); err != nil {
			return nil, fmt.Errorf("unmarshal path-info array: %w", err)
		}
		for _, e := range arr {
			if strings.TrimSpace(e.Path) == "" {
				continue
			}
			out[e.Path] = e.Signatures
		}
	case '{':
		var obj map[string]*struct {
			Signatures []string `json:"signatures"`
		}
		if err := json.Unmarshal([]byte(s), &obj); err != nil {
			return nil, fmt.Errorf("unmarshal path-info object: %w", err)
		}
		for p, e := range obj {
			if e == nil {
				return nil, fmt.Errorf("path-info: %s not present in the signed cache", p)
			}
			out[p] = e.Signatures
		}
	default:
		return nil, fmt.Errorf("unexpected path-info json (leading %q)", s[0])
	}
	return out, nil
}

// signedByKey reports whether any "name:blob" signature was made by keyName.
func signedByKey(sigs []string, keyName string) bool {
	for _, sig := range sigs {
		if name, _, ok := NormalizePubKey(sig); ok && name == keyName {
			return true
		}
	}
	return false
}
