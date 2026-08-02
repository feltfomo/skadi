package harness

import (
	"bufio"
	"context"
	"errors"
	"os"
	"os/exec"
	"strings"
	"sync"
	"syscall"
	"time"
)

// ErrEmergencyStop is returned by a LineWatcher (and surfaced on CmdResult.Err)
// when live output shows a derivation building during a phase that must not
// build anything. It trips an immediate process-group kill.
var ErrEmergencyStop = errors.New("emergency stop: unexpected build detected")

// CmdSpec describes one external command invocation.
type CmdSpec struct {
	Name string
	Args []string
	Dir  string
	Env  []string // extra environment appended to the current environment
}

// CmdResult is the outcome of running a command.
type CmdResult struct {
	Combined string // interleaved stdout+stderr, line buffered (scanned by watch)
	Stdout   string // stdout only, for stages that parse a value (store paths / revs)
	ExitCode int
	Err      error
}

// LineWatcher is invoked for every output line as it streams. Returning a
// non-nil error triggers an immediate process-group SIGKILL (emergency stop);
// that error is then attached to the CmdResult.
type LineWatcher func(line string) error

// Runner abstracts command execution so the state machine can be exercised with
// a fake in unit tests.
type Runner interface {
	Run(ctx context.Context, spec CmdSpec, watch LineWatcher) CmdResult
}

// ExecRunner is the real Runner. Each command runs in its own process group
// (Setpgid); on context cancel or a watcher stop it SIGKILLs the whole group
// (kill -pid) so no orphaned nix/qemu/disko child survives the run.
type ExecRunner struct{}

// Run executes spec, streaming each output line to watch, and returns the
// combined output and exit status.
func (ExecRunner) Run(ctx context.Context, spec CmdSpec, watch LineWatcher) CmdResult {
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()

	cmd := exec.CommandContext(ctx, spec.Name, spec.Args...)
	cmd.Dir = spec.Dir
	if len(spec.Env) > 0 {
		cmd.Env = append(os.Environ(), spec.Env...)
	}
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	// Override CommandContext's default single-process kill with a whole-group
	// SIGKILL to the negative pid.
	cmd.Cancel = func() error {
		if cmd.Process == nil {
			return nil
		}
		return syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
	}
	// Backstop the group SIGKILL: if the process (or a grandchild holding the
	// output pipe) lingers after exit or cancel, bound Wait so it returns
	// rather than blocking the reader indefinitely.
	cmd.WaitDelay = 30 * time.Second

	outR, outW, err := os.Pipe()
	if err != nil {
		return CmdResult{ExitCode: -1, Err: err}
	}
	errR, errW, err := os.Pipe()
	if err != nil {
		outW.Close()
		outR.Close()
		return CmdResult{ExitCode: -1, Err: err}
	}
	cmd.Stdout = outW
	cmd.Stderr = errW

	if err := cmd.Start(); err != nil {
		outW.Close()
		outR.Close()
		errW.Close()
		errR.Close()
		return CmdResult{ExitCode: -1, Err: err}
	}
	// The child holds its own dups; the parent drops its copies so each reader
	// sees EOF once the child exits.
	outW.Close()
	errW.Close()

	// One mutex serializes Combined + the watcher across both streams, so the
	// emergency stop trips on a build line whether nix prints it on stdout or stderr.
	var mu sync.Mutex
	var combined, stdout strings.Builder
	var watchErr error
	scan := func(r *os.File, isStdout bool, done chan<- struct{}) {
		defer close(done)
		sc := bufio.NewScanner(r)
		sc.Buffer(make([]byte, 0, 64*1024), 8*1024*1024)
		for sc.Scan() {
			line := sc.Text()
			mu.Lock()
			combined.WriteString(line)
			combined.WriteByte('\n')
			if isStdout {
				stdout.WriteString(line)
				stdout.WriteByte('\n')
			}
			if watch != nil && watchErr == nil {
				if e := watch(line); e != nil {
					watchErr = e
					cancel() // fires cmd.Cancel -> group SIGKILL
				}
			}
			mu.Unlock()
		}
	}
	outDone := make(chan struct{})
	errDone := make(chan struct{})
	go scan(outR, true, outDone)
	go scan(errR, false, errDone)

	waitErr := cmd.Wait()
	<-outDone
	<-errDone
	outR.Close()
	errR.Close()

	res := CmdResult{Combined: combined.String(), Stdout: stdout.String()}
	switch {
	case watchErr != nil:
		res.Err = watchErr
		res.ExitCode = -1
	case waitErr != nil:
		res.Err = waitErr
		var ee *exec.ExitError
		if errors.As(waitErr, &ee) {
			res.ExitCode = ee.ExitCode()
		} else {
			res.ExitCode = -1
		}
	}
	return res
}
