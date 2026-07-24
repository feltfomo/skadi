package harness

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"
)

const (
	vmFixtureRelPath     = "modules/hosts/_vm/secrets.yaml"
	vmRuntimeIdentityDir = "/run/skadi-vm-identity"
	fixedVMPasswordHash  = "$6$skadivmtest$tp5BUeNDHy1miR21O7X2QXROL/yxzqnT9XeKJ4UKI.PpyYdkise0/iV58ErEoKs5SuKbvW/xy93Mzu3lQ2Fgf0"
	fixedVMNotionToken   = "NOTION_TOKEN=REPLACE_ME"
)

type VMIdentity struct {
	Dir               string
	PrivateKeyPath    string
	PublicKeyPath     string
	PublicKeyAlgoBlob string
	Recipient         string
	Fingerprint       string
	FixturePath       string
	FixtureSHA256     string
}

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
	cfg                  Config
	runner               Runner
	log                  *log.Logger
	cache                *Cache
	server               *FileServer
	manifest             *Manifest
	signingKey           SigningKey
	repoRoot             string
	preparedSource       string
	preparedSourceHash   string
	preparedSourceStatus string
	vmIdentity           *VMIdentity
	guest                *Guest
	goldenDir            string
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
	return []stage{
		{name: "preflight", fn: h.stagePreflight},
		{name: "resolve-rev", fn: h.stageResolveRev},
		{name: "prepare-source", fn: h.stagePrepareSource},
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
		names = []string{"preflight", "resolve-rev", "prepare-source", "eval-drv", "cache-check"}
	case "gate":
		names = []string{"preflight", "resolve-rev", "prepare-source", "eval-drv", "cache-check", "build-plan-gate"}
	case "build-cache":
		names = []string{"preflight", "resolve-rev", "prepare-source", "eval-drv", "signing-key", "export-sign", "serve-cache"}
	case "provision":
		names = []string{"preflight", "resolve-rev", "prepare-source", "eval-drv", "signing-key", "export-sign", "cache-check", "build-plan-gate", "serve-cache", "guest-launch", "negative-wipe-probe", "confirm-gate", "guest-provision", "first-boot-proof"}
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
		h.manifest.ApprovedRev = full
		h.cache.Rev = full
	}
	top := h.runner.Run(ctx, CmdSpec{Name: "git", Args: []string{"rev-parse", "--show-toplevel"}}, nil)
	if top.Err != nil || top.ExitCode != 0 {
		return fmt.Errorf("resolve repo root (exit %d): %w\n%s", top.ExitCode, top.Err, top.Combined)
	}
	h.repoRoot = strings.TrimSpace(top.Stdout)
	return nil
}

func (h *Harness) stagePrepareSource(ctx context.Context) error {
	if h.repoRoot == "" {
		return fmt.Errorf("resolve-rev must run before prepare-source")
	}
	prepared := filepath.Join(h.cfg.EvidenceDir, "prepared-source")
	if err := os.RemoveAll(prepared); err != nil {
		return fmt.Errorf("reset prepared source %s: %w", prepared, err)
	}
	if res := h.runner.Run(ctx, CmdSpec{Name: "git", Args: []string{"clone", "--no-local", "--quiet", h.repoRoot, prepared}}, nil); res.Err != nil || res.ExitCode != 0 {
		return fmt.Errorf("clone prepared source (exit %d): %w\n%s", res.ExitCode, res.Err, res.Combined)
	}
	if res := h.runner.Run(ctx, CmdSpec{Name: "git", Args: []string{"-C", prepared, "checkout", "--quiet", "--detach", h.manifest.Rev}}, nil); res.Err != nil || res.ExitCode != 0 {
		return fmt.Errorf("checkout approved rev in prepared source (exit %d): %w\n%s", res.ExitCode, res.Err, res.Combined)
	}
	if head := h.runner.Run(ctx, CmdSpec{Name: "git", Args: []string{"-C", prepared, "rev-parse", "HEAD"}}, nil); head.Err != nil || head.ExitCode != 0 || strings.TrimSpace(head.Stdout) != h.manifest.Rev {
		return fmt.Errorf("prepared source HEAD mismatch: got %q want %q", strings.TrimSpace(head.Stdout), h.manifest.Rev)
	}

	identityDir := filepath.Join(h.cfg.EvidenceDir, "vm-identity")
	if err := os.RemoveAll(identityDir); err != nil {
		return fmt.Errorf("reset vm identity dir %s: %w", identityDir, err)
	}
	if err := os.MkdirAll(identityDir, 0o700); err != nil {
		return fmt.Errorf("create vm identity dir %s: %w", identityDir, err)
	}
	privateKey := filepath.Join(identityDir, "ssh_host_ed25519_key")
	publicKey := privateKey + ".pub"
	if res := h.runner.Run(ctx, CmdSpec{Name: "ssh-keygen", Args: []string{"-q", "-t", "ed25519", "-N", "", "-C", "skadi-vm-test", "-f", privateKey}}, nil); res.Err != nil || res.ExitCode != 0 {
		return fmt.Errorf("generate vm identity key (exit %d): %w\n%s", res.ExitCode, res.Err, res.Combined)
	}
	pubBytes, err := os.ReadFile(publicKey)
	if err != nil {
		return fmt.Errorf("read vm identity public key: %w", err)
	}
	algoBlob := firstTwoFields(string(pubBytes))
	if algoBlob == "" {
		return fmt.Errorf("vm identity public key is malformed")
	}
	fp := h.runner.Run(ctx, CmdSpec{Name: "ssh-keygen", Args: []string{"-lf", publicKey}}, nil)
	if fp.Err != nil || fp.ExitCode != 0 {
		return fmt.Errorf("fingerprint vm identity public key (exit %d): %w\n%s", fp.ExitCode, fp.Err, fp.Combined)
	}
	fingerprint := strings.TrimSpace(fp.Stdout)
	recipientRes := h.runner.Run(ctx, CmdSpec{Name: "ssh-to-age", Args: []string{"-i", publicKey}}, nil)
	if recipientRes.Err != nil || recipientRes.ExitCode != 0 {
		return fmt.Errorf("derive age recipient from vm key (exit %d): %w\n%s", recipientRes.ExitCode, recipientRes.Err, recipientRes.Combined)
	}
	recipient := strings.TrimSpace(recipientRes.Stdout)
	if recipient == "" {
		return fmt.Errorf("vm identity age recipient is empty")
	}

	plaintextPath := filepath.Join(identityDir, "secrets.plain.yaml")
	plaintext := fmt.Sprintf("feltfomo-password: %q\nnotion-token: %q\n", fixedVMPasswordHash, fixedVMNotionToken)
	if err := os.WriteFile(plaintextPath, []byte(plaintext), 0o600); err != nil {
		return fmt.Errorf("write vm secrets plaintext: %w", err)
	}
	defer os.Remove(plaintextPath)

	encrypted := h.runner.Run(ctx, CmdSpec{
		Name: "sops",
		Args: []string{"--encrypt", "--age", recipient, "--input-type", "yaml", "--output-type", "yaml", plaintextPath},
		Dir:  identityDir,
	}, nil)
	if encrypted.Err != nil || encrypted.ExitCode != 0 {
		return fmt.Errorf("encrypt vm secrets fixture (exit %d): %w\n%s", encrypted.ExitCode, encrypted.Err, encrypted.Combined)
	}
	fixturePath := filepath.Join(prepared, vmFixtureRelPath)
	if err := os.MkdirAll(filepath.Dir(fixturePath), 0o755); err != nil {
		return fmt.Errorf("create vm fixture dir: %w", err)
	}
	if err := os.WriteFile(fixturePath, []byte(encrypted.Stdout), 0o644); err != nil {
		return fmt.Errorf("write vm fixture: %w", err)
	}
	fixtureSHA, err := sha256File(fixturePath)
	if err != nil {
		return fmt.Errorf("hash vm fixture: %w", err)
	}

	if res := h.runner.Run(ctx, CmdSpec{Name: "git", Args: []string{"-C", prepared, "add", "--", vmFixtureRelPath}}, nil); res.Err != nil || res.ExitCode != 0 {
		return fmt.Errorf("stage vm fixture in prepared source (exit %d): %w\n%s", res.ExitCode, res.Err, res.Combined)
	}
	status := h.runner.Run(ctx, CmdSpec{Name: "git", Args: []string{"-C", prepared, "status", "--porcelain=v1"}}, nil)
	if status.Err != nil || status.ExitCode != 0 {
		return fmt.Errorf("prepared source status (exit %d): %w\n%s", status.ExitCode, status.Err, status.Combined)
	}
	statusLines := splitNonEmptyLines(status.Stdout)
	sort.Strings(statusLines)
	if len(statusLines) != 1 || !strings.HasSuffix(statusLines[0], vmFixtureRelPath) {
		return fmt.Errorf("prepared source must differ only by %s, got %v", vmFixtureRelPath, statusLines)
	}
	if err := rejectIdentityLeak(prepared); err != nil {
		return err
	}

	ageKeyPath := filepath.Join(identityDir, "age-key.txt")
	ageKey := h.runner.Run(ctx, CmdSpec{Name: "ssh-to-age", Args: []string{"-private-key", "-i", privateKey}}, nil)
	if ageKey.Err != nil || ageKey.ExitCode != 0 {
		return fmt.Errorf("derive age private key from vm identity (exit %d): %w\n%s", ageKey.ExitCode, ageKey.Err, ageKey.Combined)
	}
	if err := os.WriteFile(ageKeyPath, []byte(ageKey.Stdout), 0o600); err != nil {
		return fmt.Errorf("write temporary age key: %w", err)
	}
	defer os.Remove(ageKeyPath)
	decrypted := h.runner.Run(ctx, CmdSpec{
		Name: "sops",
		Args: []string{"--decrypt", "--output-type", "json", fixturePath},
		Dir:  identityDir,
		Env:  []string{"SOPS_AGE_KEY_FILE=" + ageKeyPath},
	}, nil)
	if decrypted.Err != nil || decrypted.ExitCode != 0 {
		return fmt.Errorf("decrypt generated vm fixture (exit %d): %w\n%s", decrypted.ExitCode, decrypted.Err, decrypted.Combined)
	}
	if err := assertExactVMSecrets(decrypted.Stdout); err != nil {
		return err
	}

	hashInput := strings.Join([]string{h.manifest.Rev, fixtureSHA, algoBlob, recipient, strings.Join(statusLines, "\n")}, "\n")
	sum := sha256.Sum256([]byte(hashInput))
	h.preparedSource = prepared
	h.preparedSourceStatus = strings.Join(statusLines, "\n")
	h.preparedSourceHash = hex.EncodeToString(sum[:])
	h.vmIdentity = &VMIdentity{
		Dir:               identityDir,
		PrivateKeyPath:    privateKey,
		PublicKeyPath:     publicKey,
		PublicKeyAlgoBlob: algoBlob,
		Recipient:         recipient,
		Fingerprint:       fingerprint,
		FixturePath:       fixturePath,
		FixtureSHA256:     fixtureSHA,
	}
	h.manifest.PreparedSourcePath = prepared
	h.manifest.PreparedSourceHash = h.preparedSourceHash
	h.manifest.PreparedSourceStatus = h.preparedSourceStatus
	h.manifest.VMIdentityRecipient = recipient
	h.manifest.VMIdentityFingerprint = fingerprint
	h.manifest.VMFixtureSHA256 = fixtureSHA
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
	show := h.runner.Run(ctx, CmdSpec{Name: "nix", Args: []string{"derivation", "show", drv}}, nil)
	if show.Err != nil || show.ExitCode != 0 {
		return fmt.Errorf("derivation show %s (exit %d): %w\n%s", drv, show.ExitCode, show.Err, show.Combined)
	}
	outPath, err := drvOutPath(show.Stdout, drv)
	if err != nil {
		return fmt.Errorf("resolve toplevel out path: %w\nstdout: %q\ncombined:\n%s", err, show.Stdout, show.Combined)
	}
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
	paths := storePathLines(res.Stdout)
	if len(paths) == 0 {
		return fmt.Errorf("realize toplevel produced no store paths\nstdout: %q\ncombined:\n%s", res.Stdout, res.Combined)
	}
	if h.manifest.StorePaths == nil {
		h.manifest.StorePaths = map[string]string{}
	}
	h.manifest.StorePaths["toplevel"] = paths[0]
	closure, err := h.cache.ClosurePaths(ctx, paths)
	if err != nil {
		return err
	}
	total := len(closure)
	started := time.Now()
	logCacheProgress(h.log, "copied", 0, total, started)
	if err := h.cache.Sign(ctx, h.signingKey, paths); err != nil {
		return err
	}
	if err := h.cache.Export(ctx, paths); err != nil {
		return err
	}
	logCacheProgress(h.log, "copied", total, total, started)
	logCacheProgress(h.log, "signed", 0, total, started)
	if err := h.cache.SignStore(ctx, h.signingKey, paths); err != nil {
		return err
	}
	verified, err := h.cache.VerifyCurrentRunKey(ctx, h.signingKey, paths)
	if err != nil {
		return err
	}
	logCacheProgress(h.log, "signed", verified, total, started)
	return nil
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
	if h.goldenDir != "" {
		h.manifest.GoldenDir = h.goldenDir
	}
	h.log.Printf("run complete for rev %s (golden: %s)", h.manifest.Rev, h.manifest.GoldenDir)
	return nil
}

func (h *Harness) flakeRef(attr string) string {
	if h.preparedSource != "" {
		return fmt.Sprintf("git+file://%s#%s", h.preparedSource, attr)
	}
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

func storePathLines(s string) []string {
	var out []string
	for _, ln := range splitNonEmptyLines(s) {
		if reStorePath.MatchString(ln) {
			out = append(out, ln)
		}
	}
	return out
}

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
	return singleStorePath(out.Path, "")
}

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

func signedByKey(sigs []string, keyName string) bool {
	for _, sig := range sigs {
		if name, _, ok := NormalizePubKey(sig); ok && name == keyName {
			return true
		}
	}
	return false
}

func assertExactVMSecrets(jsonStr string) error {
	var got map[string]string
	if err := json.Unmarshal([]byte(strings.TrimSpace(jsonStr)), &got); err != nil {
		return fmt.Errorf("parse generated vm fixture json: %w", err)
	}
	want := map[string]string{
		"feltfomo-password": fixedVMPasswordHash,
		"notion-token":      fixedVMNotionToken,
	}
	if len(got) != len(want) {
		return fmt.Errorf("generated vm fixture has wrong key count: got %d want %d", len(got), len(want))
	}
	for k, v := range want {
		if got[k] != v {
			return fmt.Errorf("generated vm fixture mismatch for %s", k)
		}
	}
	return nil
}

func rejectIdentityLeak(root string) error {
	return filepath.Walk(root, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		switch info.Name() {
		case "ssh_host_ed25519_key", "ssh_host_ed25519_key.pub":
			return fmt.Errorf("private or public vm identity leaked into prepared source: %s", path)
		}
		return nil
	})
}
