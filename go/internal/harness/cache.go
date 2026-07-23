package harness

import (
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"encoding/base64"
	"fmt"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strings"
)

// SigningKey is a per-rev Nix binary-cache signing key; the secret is written 0600 and never committed.
type SigningKey struct {
	Name       string
	SecretPath string
	Public     string // "name:base64(pub)"
}

// GenerateSigningKey returns the per-rev ed25519 signing key (libsodium
// "name:base64(secret)" layout, secret 0600). Idempotent (load-if-exists), so
// re-runs reuse the key and never invalidate the already-signed cache.
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
		// Refresh the public sidecar so it always agrees with the secret on disk.
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

// publicFromSecret re-derives the "name:base64(pub)" public key line from a
// stored "name:base64(secret)" signing-key secret.
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

// Sign signs the given store paths (recursively) with the run's key.
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

// Export copies the closure of storePaths into the file:// cache dir. Batches
// are resumable: a path already present in the cache is skipped by nix copy.
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
