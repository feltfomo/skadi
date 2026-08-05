package main

import (
	"bufio"
	"context"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"
	"time"

	"github.com/feltfomo/skadi/tools/internal/harness"
)

func main() {
	os.Exit(run())
}

// run is the sole place that decides the process exit code; it never calls
// os.Exit or log.Fatal itself beyond returning a code to main.
func run() int {
	fs := flag.NewFlagSet("rebuild-vm-golden", flag.ContinueOnError)
	var (
		rev              = fs.String("rev", "", "approved git rev to rebuild (required)")
		host             = fs.String("host", "vm", "nixos host to rebuild")
		stateDir         = fs.String("state-dir", defaultStateDir(), "run state directory")
		evidenceDir      = fs.String("evidence-dir", "", "evidence retention root (default: <state-dir>)")
		cacheDir         = fs.String("cache-dir", "", "binary cache directory (default: <state-dir>/cache)")
		trustedPublicKey = fs.String("trusted-public-key", "", "trusted binary-cache public key for gate-only runs")
		preparedSource   = fs.String("prepared-source", "", "reuse an exact retained prepared source for check or gate")
		port             = fs.Int("port", 0, "loopback cache server port (0 = auto)")
		ram              = fs.Int("ram", 8192, "guest RAM in MiB")
		cores            = fs.Int("cores", 4, "guest vCPUs")
		disk             = fs.String("disk", "48G", "guest disk size")
	)
	fs.Usage = func() {
		fmt.Fprintf(os.Stderr, "usage: rebuild-vm-golden [flags] <check|build-cache|gate|provision|all>\n\n")
		fs.PrintDefaults()
	}
	if err := fs.Parse(os.Args[1:]); err != nil {
		return 2
	}
	if fs.NArg() != 1 {
		fs.Usage()
		return 2
	}
	sub := fs.Arg(0)

	if strings.TrimSpace(*rev) == "" {
		fmt.Fprintln(os.Stderr, "error: --rev is required")
		return 2
	}
	if err := raiseNoFileLimit(); err != nil {
		fmt.Fprintf(os.Stderr, "error: raise open-file limit: %v\n", err)
		return 1
	}

	evidenceRoot := *evidenceDir
	if evidenceRoot == "" {
		evidenceRoot = *stateDir
	}
	ev, err := harness.CreateRunDir(evidenceRoot, *rev, sub, time.Now().UTC())
	if err != nil {
		fmt.Fprintf(os.Stderr, "error: create evidence run directory: %v\n", err)
		return 1
	}
	cd := *cacheDir
	if cd == "" {
		cd = filepath.Join(*stateDir, "cache")
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	cfg := harness.Config{
		Rev:              *rev,
		Host:             *host,
		StateDir:         *stateDir,
		EvidenceDir:      ev,
		CacheDir:         cd,
		TrustedPublicKey: strings.TrimSpace(*trustedPublicKey),
		PreparedSource:   strings.TrimSpace(*preparedSource),
		Port:             *port,
		RAM:              *ram,
		Cores:            *cores,
		Disk:             *disk,
		Subcommand:       sub,
		Confirm:          stdinConfirm,
	}

	h := harness.New(cfg, harness.ExecRunner{}, nil)
	manifest, err := h.Run(ctx)
	if err != nil {
		fmt.Fprintf(os.Stderr, "rebuild-vm-golden: %v\n", err)
		if manifest != nil {
			fmt.Fprintf(os.Stderr, "final stage: %s (status %s)\n", manifest.FinalStage, manifest.Status)
		}
		return 1
	}
	fmt.Printf("rebuild-vm-golden: %s complete (rev %s)\n", sub, manifest.Rev)
	return 0
}

func raiseNoFileLimit() error {
	var limit syscall.Rlimit
	if err := syscall.Getrlimit(syscall.RLIMIT_NOFILE, &limit); err != nil {
		return err
	}
	if limit.Cur == limit.Max {
		return nil
	}
	limit.Cur = limit.Max
	return syscall.Setrlimit(syscall.RLIMIT_NOFILE, &limit)
}

func defaultStateDir() string {
	if xdg := os.Getenv("XDG_STATE_HOME"); xdg != "" {
		return filepath.Join(xdg, "skadi-vm", "rebuild-vm-golden")
	}
	home, err := os.UserHomeDir()
	if err != nil || home == "" {
		return filepath.Join(os.TempDir(), "skadi-vm", "rebuild-vm-golden")
	}
	return filepath.Join(home, ".local", "state", "skadi-vm", "rebuild-vm-golden")
}

// stdinConfirm implements the interactive human gate: it prints the prompt and
// reads one line (the rev short-hash) from stdin.
func stdinConfirm(prompt string) (string, error) {
	fmt.Fprint(os.Stderr, prompt)
	sc := bufio.NewScanner(os.Stdin)
	if !sc.Scan() {
		if err := sc.Err(); err != nil {
			return "", err
		}
		return "", fmt.Errorf("no input on stdin")
	}
	return sc.Text(), nil
}
