package harness

import (
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// SigningKey is a per-run Nix binary-cache signing key; the secret is written
// 0600 and never committed.
type SigningKey struct {
	Name       string
	SecretPath string
	Public     string // "name:base64(pub)"
}

// GenerateSigningKey returns the current run's cache-signing key. Idempotent
// (load-if-exists), so rerunning a failed stage reuses the same key.
func GenerateSigningKey(evidenceDir, name string) (SigningKey, error) {
	if err := os.MkdirAll(evidenceDir, 0o700); err != nil {
		return SigningKey{}, fmt.Errorf("evidence dir: %w", err)
	}
	secretPath := filepath.Join(evidenceDir, name+".secret")
	pubPath := filepath.Join(evidenceDir, name+".public")

	if existing, err := os.ReadFile(secretPath); err == nil {
		secret := strings.TrimSpace(string(existing))
		public, derr := publicFromSecret(secret)
		if derr != nil {
			return SigningKey{}, fmt.Errorf("load existing signing key %s: %w", secretPath, derr)
		}
		if err := os.WriteFile(pubPath, []byte(public+"\n"), 0o644); err != nil {
			return SigningKey{}, fmt.Errorf("write public: %w", err)
		}
		return SigningKey{Name: name, SecretPath: secretPath, Public: public}, nil
	}

	pub, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		return SigningKey{}, fmt.Errorf("generate key: %w", err)
	}
	secret := name + ":" + base64.StdEncoding.EncodeToString(priv)
	public := name + ":" + base64.StdEncoding.EncodeToString(pub)
	if err := os.WriteFile(secretPath, []byte(secret+"\n"), 0o600); err != nil {
		return SigningKey{}, fmt.Errorf("write secret: %w", err)
	}
	if err := os.WriteFile(pubPath, []byte(public+"\n"), 0o644); err != nil {
		return SigningKey{}, fmt.Errorf("write public: %w", err)
	}
	return SigningKey{Name: name, SecretPath: secretPath, Public: public}, nil
}

func publicFromSecret(secret string) (string, error) {
	name, b64, ok := strings.Cut(secret, ":")
	if !ok {
		return "", fmt.Errorf("malformed signing-key secret (want name:base64)")
	}
	raw, err := base64.StdEncoding.DecodeString(strings.TrimSpace(b64))
	if err != nil {
		return "", fmt.Errorf("decode secret: %w", err)
	}
	if len(raw) != ed25519.PrivateKeySize {
		return "", fmt.Errorf("unexpected signing-key length %d (want %d)", len(raw), ed25519.PrivateKeySize)
	}
	priv := ed25519.PrivateKey(raw)
	pub := priv.Public().(ed25519.PublicKey)
	return name + ":" + base64.StdEncoding.EncodeToString(pub), nil
}

type FileServer struct {
	srv  *http.Server
	ln   net.Listener
	addr string
}

// StartFileServer serves dir on 127.0.0.1:port (port 0 picks a free port); loopback only.
func StartFileServer(dir string, port int) (*FileServer, error) {
	ln, err := net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", port))
	if err != nil {
		return nil, fmt.Errorf("listen: %w", err)
	}
	mux := http.NewServeMux()
	mux.Handle("/", http.FileServer(http.Dir(dir)))
	fs := &FileServer{srv: &http.Server{Handler: mux}, ln: ln, addr: ln.Addr().String()}
	go func() { _ = fs.srv.Serve(ln) }()
	return fs, nil
}

func (f *FileServer) URL() string { return "http://" + f.addr }

func (f *FileServer) Addr() string { return f.addr }

func (f *FileServer) Close(ctx context.Context) error { return f.srv.Shutdown(ctx) }

type Cache struct {
	Dir         string
	EvidenceDir string
	Rev         string
	Runner      Runner
}

func (c *Cache) KeyName() string { return "skadi-rebuild-" + shortRev(c.Rev) }

func (c *Cache) CacheKey() string { return "rebuild-vm-golden@" + shortRev(c.Rev) }

func (c *Cache) Ensure() error {
	for _, d := range []string{c.Dir, c.EvidenceDir} {
		if d == "" {
			continue
		}
		if err := os.MkdirAll(d, 0o755); err != nil {
			return fmt.Errorf("mkdir %s: %w", d, err)
		}
	}
	return nil
}

// Sign signs storePaths in the host's live store.
func (c *Cache) Sign(ctx context.Context, key SigningKey, storePaths []string) error {
	if len(storePaths) == 0 {
		return nil
	}
	args := append([]string{"store", "sign", "--key-file", key.SecretPath, "--recursive"}, storePaths...)
	res := c.Runner.Run(ctx, CmdSpec{Name: "nix", Args: args}, nil)
	if res.Err != nil || res.ExitCode != 0 {
		return fmt.Errorf("nix store sign (exit %d): %w\n%s", res.ExitCode, res.Err, res.Combined)
	}
	return nil
}

// Export copies the closure of storePaths into the shared file:// cache dir.
func (c *Cache) Export(ctx context.Context, storePaths []string) error {
	if len(storePaths) == 0 {
		return nil
	}
	args := append([]string{"copy", "--to", "file://" + c.Dir}, storePaths...)
	res := c.Runner.Run(ctx, CmdSpec{Name: "nix", Args: args}, nil)
	if res.Err != nil || res.ExitCode != 0 {
		return fmt.Errorf("nix copy (exit %d): %w\n%s", res.ExitCode, res.Err, res.Combined)
	}
	return nil
}

// SignStore refreshes signatures in the shared file:// cache without recopying paths.
func (c *Cache) SignStore(ctx context.Context, key SigningKey, storePaths []string) error {
	if len(storePaths) == 0 {
		return nil
	}
	args := append([]string{"store", "sign", "--store", "file://" + c.Dir, "--key-file", key.SecretPath, "--recursive"}, storePaths...)
	res := c.Runner.Run(ctx, CmdSpec{Name: "nix", Args: args}, nil)
	if res.Err != nil || res.ExitCode != 0 {
		return fmt.Errorf("nix store sign --store file://%s (exit %d): %w\n%s", c.Dir, res.ExitCode, res.Err, res.Combined)
	}
	return nil
}

// ClosurePaths lists the recursive closure paths for the given roots in the live store.
func (c *Cache) ClosurePaths(ctx context.Context, storePaths []string) ([]string, error) {
	if len(storePaths) == 0 {
		return nil, nil
	}
	args := append([]string{"path-info", "--recursive", "--json"}, storePaths...)
	res := c.Runner.Run(ctx, CmdSpec{Name: "nix", Args: args}, nil)
	if res.Err != nil || res.ExitCode != 0 {
		return nil, fmt.Errorf("nix path-info (exit %d): %w\n%s", res.ExitCode, res.Err, res.Combined)
	}
	return parsePathInfoPaths(res.Stdout)
}

// VerifyCurrentRunKey proves every cache path in the recursive closure carries the current run key.
func (c *Cache) VerifyCurrentRunKey(ctx context.Context, key SigningKey, storePaths []string) (int, error) {
	if len(storePaths) == 0 {
		return 0, nil
	}
	args := append([]string{"path-info", "--store", "file://" + c.Dir, "--recursive", "--sigs", "--json"}, storePaths...)
	res := c.Runner.Run(ctx, CmdSpec{Name: "nix", Args: args}, nil)
	if res.Err != nil || res.ExitCode != 0 {
		return 0, fmt.Errorf("nix path-info --store file://%s (exit %d): %w\n%s", c.Dir, res.ExitCode, res.Err, res.Combined)
	}
	closure, err := parsePathInfoSigs(res.Stdout)
	if err != nil {
		return 0, err
	}
	if len(closure) == 0 {
		return 0, fmt.Errorf("signature verification returned an empty closure for %v", storePaths)
	}
	for _, root := range storePaths {
		if _, ok := closure[root]; !ok {
			return 0, fmt.Errorf("signature verification closure is missing requested root %s", root)
		}
	}
	for path, sigs := range closure {
		if !signedByKey(sigs, key.Name) {
			return 0, fmt.Errorf("cache path %s is not signed by %s", path, key.Name)
		}
	}
	return len(closure), nil
}

// Inventory lists the .narinfo entries currently in the cache dir.
func (c *Cache) Inventory() ([]string, error) {
	entries, err := os.ReadDir(c.Dir)
	if err != nil {
		return nil, fmt.Errorf("read cache dir: %w", err)
	}
	var out []string
	for _, e := range entries {
		if strings.HasSuffix(e.Name(), ".narinfo") {
			out = append(out, e.Name())
		}
	}
	return out, nil
}

func shortRev(rev string) string {
	rev = strings.TrimSpace(rev)
	if len(rev) > 12 {
		return rev[:12]
	}
	return rev
}

func parsePathInfoPaths(jsonStr string) ([]string, error) {
	s := strings.TrimSpace(jsonStr)
	if s == "" {
		return nil, nil
	}
	var out []string
	switch s[0] {
	case '[':
		var arr []struct {
			Path string `json:"path"`
		}
		if err := json.Unmarshal([]byte(s), &arr); err != nil {
			return nil, fmt.Errorf("unmarshal path-info array: %w", err)
		}
		for _, e := range arr {
			if e.Path != "" {
				out = append(out, e.Path)
			}
		}
	case '{':
		var obj map[string]json.RawMessage
		if err := json.Unmarshal([]byte(s), &obj); err != nil {
			return nil, fmt.Errorf("unmarshal path-info object: %w", err)
		}
		for path := range obj {
			out = append(out, path)
		}
	default:
		return nil, fmt.Errorf("unexpected path-info json (leading %q)", s[0])
	}
	return out, nil
}

func logCacheProgress(logger *log.Logger, phase string, done, total int, started time.Time) {
	if logger == nil {
		return
	}
	logger.Printf("export-sign: %s %d/%d (%s)", phase, done, total, time.Since(started).Round(time.Second))
}
