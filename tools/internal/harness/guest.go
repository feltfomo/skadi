package harness

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

// Guest is one QEMU VM the harness drives over SSH. Destruction happens only
// inside the guest against its own /dev/vda; QEMU runs in a goroutine and is
// reaped on cancel via the runner's process-group SIGKILL.
type Guest struct {
	h        *Harness
	label    string
	disk     string
	vars     string
	serial   string
	iso      string
	sshPort  int
	sshKey   string
	ovmfCode string
	cancel   context.CancelFunc
	done     chan CmdResult
	res      CmdResult
}

func (h *Harness) newGuest(label, disk, vars, serial string) (*Guest, error) {
	ovmf := os.Getenv("OVMF_FD")
	if ovmf == "" {
		return nil, fmt.Errorf("OVMF_FD is not set (should be provided by the rebuild-vm-golden nix wrapper)")
	}
	code := filepath.Join(ovmf, "FV", "OVMF_CODE.fd")
	if _, err := os.Stat(code); err != nil {
		return nil, fmt.Errorf("OVMF_CODE.fd not found at %s: %w", code, err)
	}
	sshKey := os.Getenv("SKADI_VM_TEST_SSH_KEY")
	if sshKey == "" {
		home, _ := os.UserHomeDir()
		sshKey = filepath.Join(home, ".cache", "skadi-vm", "vm-test-key")
	}
	if _, err := os.Stat(sshKey); err != nil {
		return nil, fmt.Errorf("vm-test ssh private key not found at %s (set SKADI_VM_TEST_SSH_KEY): %w", sshKey, err)
	}
	port, err := freePort()
	if err != nil {
		return nil, err
	}
	return &Guest{
		h: h, label: label, disk: disk, vars: vars, serial: serial,
		sshPort: port, sshKey: sshKey, ovmfCode: code,
	}, nil
}

func (h *Harness) guestWorkDir() string {
	return filepath.Join(h.cfg.EvidenceDir, "guest")
}

func (h *Harness) servedSubstituter() (string, error) {
	if h.server == nil {
		return "", fmt.Errorf("cache file server is not running; serve-cache must precede the guest stages")
	}
	u, err := url.Parse(h.server.URL())
	if err != nil {
		return "", fmt.Errorf("parse served cache url %q: %w", h.server.URL(), err)
	}
	port := u.Port()
	if port == "" {
		return "", fmt.Errorf("served cache url %q has no port", h.server.URL())
	}
	return "http://10.0.2.2:" + port, nil
}

func (h *Harness) guestNixConfig() (string, error) {
	sub, err := h.servedSubstituter()
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("substituters = %s https://cache.nixos.org\ntrusted-public-keys = %s cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=\nrequire-sigs = true\nalways-allow-substitutes = true", sub, strings.TrimSpace(h.manifest.PublicKey)), nil
}

const guestSrcDir = "/tmp/skadi-install"

func (h *Harness) servedSourceURL() (string, error) {
	base, err := h.servedSubstituter()
	if err != nil {
		return "", err
	}
	return strings.TrimSuffix(base, "/") + "/skadi-src.tar.gz", nil
}

func (h *Harness) prepareGuestSource(ctx context.Context) error {
	if h.preparedSource == "" {
		return fmt.Errorf("prepared source is empty; prepare-source must run first")
	}
	if err := rejectIdentityLeak(h.preparedSource); err != nil {
		return err
	}
	if err := h.cache.Ensure(); err != nil {
		return err
	}
	tarball := filepath.Join(h.cfg.CacheDir, "skadi-src.tar.gz")
	_ = os.Remove(tarball)
	if r := h.runner.Run(ctx, CmdSpec{Name: "tar", Args: []string{"-czf", tarball, "-C", h.preparedSource, "."}}, nil); r.Err != nil || r.ExitCode != 0 {
		return fmt.Errorf("package prepared source (exit %d): %w\n%s", r.ExitCode, r.Err, r.Combined)
	}
	if sum, err := sha256File(tarball); err == nil {
		h.manifest.SourceTarballSHA256 = sum
	}
	return nil
}

func (h *Harness) stageSourceIntoGuest(ctx context.Context) error {
	g := h.guest
	if g == nil {
		return fmt.Errorf("guest not launched")
	}
	srcURL, err := h.servedSourceURL()
	if err != nil {
		return err
	}
	cmd := strings.Join([]string{
		"set -e",
		"rm -rf " + guestSrcDir,
		"mkdir -p " + guestSrcDir,
		fmt.Sprintf("curl -fsSL %s -o /tmp/skadi-src.tar.gz", shellSingleQuote(srcURL)),
		"tar -xzf /tmp/skadi-src.tar.gz -C " + guestSrcDir,
		"test -d " + guestSrcDir + "/.git",
	}, " && ")
	res := g.ssh(ctx, cmd)
	if res.Err != nil || res.ExitCode != 0 {
		return fmt.Errorf("stage prepared source into guest (exit %d): %w\n%s", res.ExitCode, res.Err, res.Combined)
	}
	h.log.Printf("staged prepared source into guest at %s", guestSrcDir)
	return nil
}

func (h *Harness) stageRuntimeIdentityToGuest(ctx context.Context) error {
	g := h.guest
	if g == nil {
		return fmt.Errorf("guest not launched")
	}
	if h.vmIdentity == nil {
		return fmt.Errorf("vm identity not prepared")
	}
	prep := g.ssh(ctx, "install -d -m0700 "+vmRuntimeIdentityDir)
	if prep.Err != nil || prep.ExitCode != 0 {
		return fmt.Errorf("prepare guest runtime identity dir (exit %d): %w\n%s", prep.ExitCode, prep.Err, prep.Combined)
	}
	if res := g.scp(ctx, h.vmIdentity.PrivateKeyPath, vmRuntimeIdentityDir+"/ssh_host_ed25519_key.tmp"); res.Err != nil || res.ExitCode != 0 {
		return fmt.Errorf("scp vm private key into guest (exit %d): %w\n%s", res.ExitCode, res.Err, res.Combined)
	}
	if res := g.scp(ctx, h.vmIdentity.PublicKeyPath, vmRuntimeIdentityDir+"/ssh_host_ed25519_key.pub.tmp"); res.Err != nil || res.ExitCode != 0 {
		return fmt.Errorf("scp vm public key into guest (exit %d): %w\n%s", res.ExitCode, res.Err, res.Combined)
	}
	install := g.ssh(ctx, strings.Join([]string{
		"install -m0600 " + vmRuntimeIdentityDir + "/ssh_host_ed25519_key.tmp " + vmRuntimeIdentityDir + "/ssh_host_ed25519_key",
		"install -m0644 " + vmRuntimeIdentityDir + "/ssh_host_ed25519_key.pub.tmp " + vmRuntimeIdentityDir + "/ssh_host_ed25519_key.pub",
		"rm -f " + vmRuntimeIdentityDir + "/ssh_host_ed25519_key.tmp " + vmRuntimeIdentityDir + "/ssh_host_ed25519_key.pub.tmp",
	}, " && "))
	if install.Err != nil || install.ExitCode != 0 {
		return fmt.Errorf("install vm runtime identity in guest (exit %d): %w\n%s", install.ExitCode, install.Err, install.Combined)
	}
	verify := g.ssh(ctx, "ssh-keygen -y -f "+vmRuntimeIdentityDir+"/ssh_host_ed25519_key")
	if verify.Err != nil || verify.ExitCode != 0 {
		return fmt.Errorf("verify guest runtime identity (exit %d): %w\n%s", verify.ExitCode, verify.Err, verify.Combined)
	}
	if firstTwoFields(verify.Stdout) != h.vmIdentity.PublicKeyAlgoBlob {
		return fmt.Errorf("guest runtime identity mismatch after transfer")
	}
	return nil
}

func (h *Harness) buildInstallerISO(ctx context.Context) (string, error) {
	attr := "nixosConfigurations.installer.config.system.build.isoImage"
	res := h.runner.Run(ctx, CmdSpec{Name: "nix", Args: []string{"build", "--no-link", "--print-out-paths", h.flakeRef(attr)}}, nil)
	if res.Err != nil || res.ExitCode != 0 {
		return "", fmt.Errorf("build installer ISO (exit %d): %w\n%s", res.ExitCode, res.Err, res.Combined)
	}
	out := lastNonEmpty(res.Stdout)
	if out == "" {
		return "", fmt.Errorf("installer ISO build printed no store path")
	}
	isoDir := filepath.Join(out, "iso")
	entries, err := os.ReadDir(isoDir)
	if err != nil {
		return "", fmt.Errorf("read iso dir %s: %w", isoDir, err)
	}
	for _, e := range entries {
		if strings.HasSuffix(e.Name(), ".iso") {
			return filepath.Join(isoDir, e.Name()), nil
		}
	}
	return "", fmt.Errorf("no .iso found under %s", isoDir)
}

func (g *Guest) createDisk(ctx context.Context, size string) error {
	if size == "" {
		size = "48G"
	}
	res := g.h.runner.Run(ctx, CmdSpec{Name: "qemu-img", Args: []string{"create", "-f", "qcow2", g.disk, size}}, nil)
	if res.Err != nil || res.ExitCode != 0 {
		return fmt.Errorf("qemu-img create %s (exit %d): %w\n%s", g.disk, res.ExitCode, res.Err, res.Combined)
	}
	return nil
}

func (g *Guest) seedVars() error {
	src := filepath.Join(os.Getenv("OVMF_FD"), "FV", "OVMF_VARS.fd")
	if err := copyFile(src, g.vars, 0o600); err != nil {
		return fmt.Errorf("seed OVMF vars from %s: %w", src, err)
	}
	return nil
}

func (g *Guest) boot(ctx context.Context, bootOrder, iso string) error {
	if f, err := os.Create(g.serial); err == nil {
		f.Close()
	} else {
		return fmt.Errorf("create serial log %s: %w", g.serial, err)
	}
	ram := g.h.cfg.RAM
	if ram <= 0 {
		ram = 8192
	}
	cores := g.h.cfg.Cores
	if cores <= 0 {
		cores = 4
	}
	args := []string{
		"-machine", "q35,accel=kvm",
		"-cpu", "host",
		"-m", strconv.Itoa(ram),
		"-smp", strconv.Itoa(cores),
		"-drive", "if=pflash,format=raw,readonly=on,file=" + g.ovmfCode,
		"-drive", "if=pflash,format=raw,file=" + g.vars,
		"-drive", "file=" + g.disk + ",if=virtio,format=qcow2",
		"-netdev", fmt.Sprintf("user,id=net0,hostfwd=tcp:127.0.0.1:%d-:22", g.sshPort),
		"-device", "virtio-net,netdev=net0",
		"-display", "none",
		"-serial", "file:" + g.serial,
		"-no-reboot",
		"-boot", "order=" + bootOrder,
	}
	if iso != "" {
		args = append(args, "-cdrom", iso)
	}
	qctx, cancel := context.WithCancel(ctx)
	g.cancel = cancel
	g.done = make(chan CmdResult, 1)
	go func(done chan CmdResult) {
		done <- g.h.runner.Run(qctx, CmdSpec{Name: "qemu-system-x86_64", Args: args}, nil)
	}(g.done)
	return nil
}

func (g *Guest) exited() bool {
	if g.done == nil {
		return true
	}
	select {
	case r := <-g.done:
		g.res = r
		g.done = nil
		return true
	default:
		return false
	}
}

func (g *Guest) ssh(ctx context.Context, remote string) CmdResult {
	return g.sshWatch(ctx, remote, nil)
}

func (g *Guest) sshWatch(ctx context.Context, remote string, watch LineWatcher) CmdResult {
	args := []string{
		"-i", g.sshKey,
		"-p", strconv.Itoa(g.sshPort),
		"-o", "StrictHostKeyChecking=no",
		"-o", "UserKnownHostsFile=/dev/null",
		"-o", "LogLevel=ERROR",
		"-o", "ConnectTimeout=5",
		"-o", "BatchMode=yes",
		"root@127.0.0.1", remote,
	}
	return g.h.runner.Run(ctx, CmdSpec{Name: "ssh", Args: args}, watch)
}

func (g *Guest) scp(ctx context.Context, localPath, remotePath string) CmdResult {
	args := []string{
		"-i", g.sshKey,
		"-P", strconv.Itoa(g.sshPort),
		"-o", "StrictHostKeyChecking=no",
		"-o", "UserKnownHostsFile=/dev/null",
		"-o", "LogLevel=ERROR",
		localPath,
		"root@127.0.0.1:" + remotePath,
	}
	return g.h.runner.Run(ctx, CmdSpec{Name: "scp", Args: args}, nil)
}

func (g *Guest) waitSSH(ctx context.Context) error {
	deadline := time.Now().Add(15 * time.Minute)
	for time.Now().Before(deadline) {
		if ctx.Err() != nil {
			return ctx.Err()
		}
		if g.exited() {
			return fmt.Errorf("qemu %s exited before ssh came up (exit %d): %w\nserial tail:\n%s", g.label, g.res.ExitCode, g.res.Err, tailFile(g.serial, 40))
		}
		if r := g.ssh(ctx, "true"); r.Err == nil && r.ExitCode == 0 {
			return nil
		}
		time.Sleep(5 * time.Second)
	}
	return fmt.Errorf("guest %s never accepted ssh within timeout\nserial tail:\n%s", g.label, tailFile(g.serial, 40))
}

func (g *Guest) waitLogin(ctx context.Context) error {
	deadline := time.Now().Add(15 * time.Minute)
	for time.Now().Before(deadline) {
		if ctx.Err() != nil {
			return ctx.Err()
		}
		if g.exited() {
			return fmt.Errorf("qemu %s exited before login (exit %d)\nserial tail:\n%s", g.label, g.res.ExitCode, tailFile(g.serial, 40))
		}
		if data, err := os.ReadFile(g.serial); err == nil {
			s := string(data)
			if strings.Contains(s, "login:") || strings.Contains(s, "Reached target Multi-User") || strings.Contains(s, "Startup finished") {
				return nil
			}
		}
		time.Sleep(5 * time.Second)
	}
	return fmt.Errorf("guest %s never reached a login prompt\nserial tail:\n%s", g.label, tailFile(g.serial, 40))
}

func (g *Guest) poweroff(ctx context.Context) error {
	shutdown := g.ssh(ctx, "poweroff")
	deadline := time.Now().Add(90 * time.Second)
	for time.Now().Before(deadline) {
		if g.exited() {
			g.cancel = nil
			return validatePoweroffOutcome(shutdown.ExitCode, true, g.res.ExitCode, g.res.Err)
		}
		time.Sleep(2 * time.Second)
	}
	g.stop()
	g.cancel = nil
	return validatePoweroffOutcome(shutdown.ExitCode, false, g.res.ExitCode, g.res.Err)
}

func validatePoweroffOutcome(sshExit int, exited bool, qemuExit int, qemuErr error) error {
	if sshExit != 0 && sshExit != 255 {
		return fmt.Errorf("guest poweroff command failed with exit %d", sshExit)
	}
	if !exited {
		return fmt.Errorf("guest did not power off within 90 seconds")
	}
	if qemuErr != nil || qemuExit != 0 {
		return fmt.Errorf("qemu exited uncleanly after poweroff (exit %d): %w", qemuExit, qemuErr)
	}
	return nil
}

func parseUnitState(output string) (string, error) {
	state := strings.TrimSpace(output)
	if state == "" || strings.Contains(state, "\n") {
		return "", fmt.Errorf("malformed unit state %q", output)
	}
	return state, nil
}

func parseQemuImgCheck(output string) error {
	if !strings.Contains(output, "No errors were found on the image") {
		return fmt.Errorf("qemu-img check did not report a clean image: %q", strings.TrimSpace(output))
	}
	return nil
}

func (h *Harness) checkGuestDisk(ctx context.Context, phase string, g *Guest) error {
	res := h.runner.Run(ctx, CmdSpec{Name: "qemu-img", Args: []string{"check", g.disk}}, nil)
	observed := strings.TrimSpace(res.Stdout)
	match := res.Err == nil && res.ExitCode == 0 && parseQemuImgCheck(res.Combined) == nil
	h.manifest.Checks = append(h.manifest.Checks, Proof{Name: phase + " qcow2 integrity", Expected: "clean", Observed: observed, Match: match})
	if !match {
		return fmt.Errorf("%s qcow2 integrity failed (exit %d): %w\n%s", phase, res.ExitCode, res.Err, res.Combined)
	}
	return nil
}

func (h *Harness) assertVarsWritable(phase string, path string) error {
	f, err := os.OpenFile(path, os.O_WRONLY, 0)
	match := err == nil
	if f != nil {
		_ = f.Close()
	}
	h.manifest.Checks = append(h.manifest.Checks, Proof{Name: phase + " OVMF vars writable", Expected: "writable", Observed: fmt.Sprint(match), Match: match})
	if err != nil {
		return fmt.Errorf("%s OVMF vars are not writable at %s: %w", phase, path, err)
	}
	return nil
}

func (g *Guest) stop() {
	if g.cancel != nil {
		g.cancel()
	}
	deadline := time.Now().Add(35 * time.Second)
	for time.Now().Before(deadline) {
		if g.exited() {
			return
		}
		time.Sleep(time.Second)
	}
}

func (h *Harness) stageGuestLaunch(ctx context.Context) error {
	if _, err := os.Stat("/dev/vda"); err == nil {
		return fmt.Errorf("refusing to launch: host exposes /dev/vda; a misfired wipe could target the host")
	}
	if h.server == nil {
		return fmt.Errorf("serve-cache must run before guest-launch")
	}
	iso, err := h.buildInstallerISO(ctx)
	if err != nil {
		return err
	}
	work := h.guestWorkDir()
	if err := os.MkdirAll(work, 0o755); err != nil {
		return fmt.Errorf("create guest work dir %s: %w", work, err)
	}
	if err := h.prepareGuestSource(ctx); err != nil {
		return err
	}
	g, err := h.newGuest("installer", filepath.Join(work, h.cfg.Host+".qcow2"), filepath.Join(work, "vm-vars.fd"), filepath.Join(work, h.cfg.Host+"-serial.log"))
	if err != nil {
		return err
	}
	g.iso = iso
	if err := g.createDisk(ctx, h.cfg.Disk); err != nil {
		return err
	}
	if err := g.seedVars(); err != nil {
		return err
	}
	if err := g.boot(ctx, "dc", iso); err != nil {
		return err
	}
	h.guest = g
	h.log.Printf("guest %q booting installer ISO %s (ssh :%d, serial %s)", h.cfg.Host, iso, g.sshPort, g.serial)
	if err := g.waitSSH(ctx); err != nil {
		return err
	}
	if err := h.stageSourceIntoGuest(ctx); err != nil {
		return err
	}
	if err := h.stageRuntimeIdentityToGuest(ctx); err != nil {
		return err
	}
	return nil
}

func (h *Harness) stageNegativeWipeProbe(ctx context.Context) error {
	g := h.guest
	if g == nil {
		return fmt.Errorf("guest not launched")
	}
	lb := g.ssh(ctx, "lsblk --nodeps --noheadings --output NAME,TYPE")
	if lb.Err != nil || lb.ExitCode != 0 {
		return fmt.Errorf("guest lsblk (exit %d): %w\n%s", lb.ExitCode, lb.Err, lb.Combined)
	}
	var disks []string
	for _, ln := range strings.Split(lb.Stdout, "\n") {
		f := strings.Fields(ln)
		if len(f) == 2 && f[1] == "disk" {
			disks = append(disks, "/dev/"+f[0])
		}
	}
	if len(disks) != 1 || disks[0] != "/dev/vda" {
		return fmt.Errorf("negative-wipe probe: guest exposes disks %v, expected exactly [/dev/vda]", disks)
	}
	nixConf, err := h.guestNixConfig()
	if err != nil {
		return err
	}
	probe := fmt.Sprintf("cd %s && NIX_CONFIG=%s disko --dry-run --mode destroy,format,mount --flake .#%s", guestSrcDir, shellSingleQuote(nixConf), h.cfg.Host)
	res := g.ssh(ctx, probe)
	if res.Err != nil || res.ExitCode != 0 {
		return fmt.Errorf("guest disko --dry-run (exit %d): %w\n%s", res.ExitCode, res.Err, res.Combined)
	}
	script, err := diskoScriptPath(res.Stdout)
	if err != nil {
		return fmt.Errorf("negative-wipe probe: %w\nstdout: %q\ncombined:\n%s", err, res.Stdout, res.Combined)
	}
	cat := g.ssh(ctx, "cat "+shellSingleQuote(script))
	if cat.Err != nil || cat.ExitCode != 0 {
		return fmt.Errorf("read disko script %s in guest (exit %d): %w\n%s", script, cat.ExitCode, cat.Err, cat.Combined)
	}
	devs := scanDiskoDevices(cat.Stdout)
	if len(devs) != 1 || devs[0] != "/dev/vda" {
		return fmt.Errorf("negative-wipe probe: disko script %s targets %v, expected exactly [/dev/vda]", script, devs)
	}
	deriver := g.ssh(ctx, "nix-store --query --deriver "+shellSingleQuote(script))
	if deriver.Err != nil || deriver.ExitCode != 0 {
		return fmt.Errorf("query live disko script deriver (exit %d): %w\n%s", deriver.ExitCode, deriver.Err, deriver.Combined)
	}
	observedDrv, err := singleStorePath(deriver.Stdout, ".drv")
	if err != nil {
		return fmt.Errorf("parse live disko script deriver: %w", err)
	}
	expectedDrv := h.manifest.DrvPaths["disko"]
	if expectedDrv == "" {
		return fmt.Errorf("disko proof cannot run without an expected drvPath")
	}
	return h.recordDrvComparison("live disko --dry-run", expectedDrv, observedDrv)
}

func (h *Harness) stageGuestProvision(ctx context.Context) error {
	g := h.guest
	if g == nil {
		return fmt.Errorf("guest not launched")
	}
	nixConf, err := h.guestNixConfig()
	if err != nil {
		return err
	}
	remote := fmt.Sprintf("NIX_CONFIG=%s IN_DISKO_TEST=1 SKADI_INSTALL_UNATTENDED=1 SKADI_INSTALL_SOURCE=%s SKADI_VM_TEST_IDENTITY_DIR=%s skadi-install %s --yes-wipe-all-disks", shellSingleQuote(nixConf), shellSingleQuote(guestSrcDir), shellSingleQuote(vmRuntimeIdentityDir), shellSingleQuote(h.cfg.Host))
	var violation string
	watch := buildGateWatcher(func(v string) { violation = v })
	res := g.sshWatch(ctx, remote, watch)
	logPath := filepath.Join(h.guestWorkDir(), h.cfg.Host+"-install.log")
	if err := os.WriteFile(logPath, []byte(res.Combined), 0o644); err == nil {
		if sum, e := sha256File(logPath); e == nil {
			h.manifest.InstallLogSHA256 = sum
		}
	}
	plan := ScanBuildPlan(res.Combined)
	h.recordProvisionBuildCount(plan)
	if errors.Is(res.Err, ErrEmergencyStop) {
		return fmt.Errorf("%w: build announced during guest install: %s (log: %s)", ErrEmergencyStop, violation, logPath)
	}
	if !plan.IsClean() {
		return fmt.Errorf("guest install would build %d derivation(s) (golden requires 0): %s", plan.BuildCount(), strings.Join(plan.WillBuild, ", "))
	}
	if res.Err != nil || res.ExitCode != 0 {
		return fmt.Errorf("guest skadi-install failed (exit %d): %w\ninstall log: %s", res.ExitCode, res.Err, logPath)
	}
	if err := g.poweroff(ctx); err != nil {
		return err
	}
	return nil
}

func (h *Harness) recordProvisionBuildCount(plan BuildPlan) {
	h.manifest.ProvisionBuildCount = intPtr(plan.BuildCount())
}

func (h *Harness) stageFirstBootProof(ctx context.Context) error {
	g := h.guest
	if g == nil {
		return fmt.Errorf("guest not launched")
	}
	g.serial = filepath.Join(h.guestWorkDir(), h.cfg.Host+"-firstboot-serial.log")
	if err := g.boot(ctx, "cd", ""); err != nil {
		return err
	}
	if err := g.waitLogin(ctx); err != nil {
		return err
	}
	if err := g.waitSSH(ctx); err != nil {
		return err
	}
	if err := h.assertVarsWritable("first boot", g.vars); err != nil {
		return err
	}
	if err := h.assertGuestIdentity(ctx, "first boot"); err != nil {
		return err
	}
	if sum, e := sha256File(g.serial); e == nil {
		h.manifest.FirstBootSerialSHA256 = sum
	}
	if err := g.poweroff(ctx); err != nil {
		return err
	}
	return h.checkGuestDisk(ctx, "first boot", g)
}

func (h *Harness) assertGuestIdentity(ctx context.Context, phase string) error {
	g := h.guest
	if h.vmIdentity == nil {
		return fmt.Errorf("vm identity not prepared")
	}
	obs := g.ssh(ctx, "cat /etc/ssh/ssh_host_ed25519_key.pub")
	if obs.Err != nil || obs.ExitCode != 0 {
		return fmt.Errorf("read guest host pubkey (exit %d): %w\n%s", obs.ExitCode, obs.Err, obs.Combined)
	}
	gotAlgoBlob := firstTwoFields(obs.Stdout)
	idMatch := gotAlgoBlob == h.vmIdentity.PublicKeyAlgoBlob
	h.manifest.Identity = append(h.manifest.Identity, IdentityProof{
		Name:     phase + " ssh_host_ed25519_key.pub",
		Expected: h.vmIdentity.PublicKeyAlgoBlob,
		Observed: gotAlgoBlob,
		Match:    idMatch,
	})
	if !idMatch {
		return fmt.Errorf("installed vm host identity does not match this run's generated key")
	}

	hn := g.ssh(ctx, "hostname")
	if hn.Err != nil || hn.ExitCode != 0 {
		return fmt.Errorf("read guest hostname (exit %d): %w\n%s", hn.ExitCode, hn.Err, hn.Combined)
	}
	host := strings.TrimSpace(hn.Stdout)
	hostMatch := host == h.cfg.Host
	h.manifest.Identity = append(h.manifest.Identity, IdentityProof{Name: phase + " hostname", Expected: h.cfg.Host, Observed: host, Match: hostMatch})
	if !hostMatch {
		return fmt.Errorf("guest hostname mismatch: expected %q got %q", h.cfg.Host, host)
	}

	want := h.manifest.StorePaths["toplevel"]
	if want == "" {
		return fmt.Errorf("toplevel proof cannot run without an expected store path")
	}
	{
		tp := g.ssh(ctx, "readlink -f /run/current-system")
		if tp.Err != nil || tp.ExitCode != 0 {
			return fmt.Errorf("read guest toplevel (exit %d): %w\n%s", tp.ExitCode, tp.Err, tp.Combined)
		}
		got := strings.TrimSpace(tp.Stdout)
		tpMatch := got == want
		h.manifest.Identity = append(h.manifest.Identity, IdentityProof{Name: phase + " toplevel", Expected: want, Observed: got, Match: tpMatch})
		if !tpMatch {
			return fmt.Errorf("guest toplevel mismatch: expected %q got %q", want, got)
		}
	}

	pw := g.ssh(ctx, "cat /run/secrets-for-users/feltfomo-password")
	if pw.Err != nil || pw.ExitCode != 0 {
		return fmt.Errorf("read feltfomo password secret (exit %d): %w\n%s", pw.ExitCode, pw.Err, pw.Combined)
	}
	token := g.ssh(ctx, "cat /run/secrets/notion-token")
	if token.Err != nil || token.ExitCode != 0 {
		return fmt.Errorf("read notion token secret (exit %d): %w\n%s", token.ExitCode, token.Err, token.Combined)
	}
	secretSpecs := []struct {
		name  string
		path  string
		value string
		read  CmdResult
	}{
		{name: "feltfomo-password", path: "/run/secrets-for-users/feltfomo-password", value: fixedVMPasswordHash, read: pw},
		{name: "notion-token", path: "/run/secrets/notion-token", value: fixedVMNotionToken, read: token},
	}
	for _, spec := range secretSpecs {
		hash := g.ssh(ctx, "sha256sum "+shellSingleQuote(spec.path))
		fields := strings.Fields(hash.Stdout)
		if hash.Err != nil || hash.ExitCode != 0 || len(fields) != 2 {
			return fmt.Errorf("hash secret proof for %s (exit %d): %w\n%s", spec.name, hash.ExitCode, hash.Err, hash.Combined)
		}
		proof := SecretProof{
			Name:   phase + " " + spec.name,
			SHA256: fields[0],
			Match:  strings.TrimSpace(spec.read.Stdout) == spec.value,
		}
		h.manifest.Secrets = append(h.manifest.Secrets, proof)
		if !proof.Match {
			return fmt.Errorf("secret proof failed for %s", proof.Name)
		}
	}

	notionSync := g.ssh(ctx, "command -v notion-sync")
	notionObserved := strings.TrimSpace(notionSync.Stdout)
	notionMatch := notionSync.Err == nil && notionSync.ExitCode == 0 && notionObserved != ""
	h.manifest.Checks = append(h.manifest.Checks, Proof{Name: phase + " notion-sync present", Expected: "present", Observed: notionObserved, Match: notionMatch})
	if !notionMatch {
		return fmt.Errorf("notion-sync is not present in guest (exit %d): %w\n%s", notionSync.ExitCode, notionSync.Err, notionSync.Combined)
	}

	sshd := g.ssh(ctx, "systemctl is-active sshd")
	sshdState, stateErr := parseUnitState(sshd.Stdout)
	sshdMatch := sshd.Err == nil && sshd.ExitCode == 0 && stateErr == nil && sshdState == "active"
	h.manifest.Checks = append(h.manifest.Checks, Proof{Name: phase + " sshd active", Expected: "active", Observed: sshdState, Match: sshdMatch})
	if !sshdMatch {
		return fmt.Errorf("sshd is not active (exit %d): %w\n%s", sshd.ExitCode, sshd.Err, sshd.Combined)
	}

	fu := g.ssh(ctx, "systemctl --failed --no-legend --plain")
	if fu.Err != nil || fu.ExitCode != 0 {
		return fmt.Errorf("query failed guest units (exit %d): %w\n%s", fu.ExitCode, fu.Err, fu.Combined)
	}
	failedUnits := strings.TrimSpace(fu.Stdout)
	h.manifest.Checks = append(h.manifest.Checks, Proof{Name: phase + " failed units", Expected: "none", Observed: failedUnits, Match: failedUnits == ""})
	if failedUnits != "" {
		return fmt.Errorf("guest has failed units:\n%s", fu.Combined)
	}
	return nil
}

func (h *Harness) stageFreeze(ctx context.Context) error {
	_ = ctx
	g := h.guest
	if g == nil {
		return fmt.Errorf("guest not launched")
	}
	dir := h.cfg.StateDir
	if dir == "" {
		return fmt.Errorf("state-dir is required to freeze the golden")
	}
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return fmt.Errorf("create golden dir %s: %w", dir, err)
	}
	h.goldenDir = dir
	qcow := filepath.Join(dir, "program-files-base.qcow2")
	vars := filepath.Join(dir, "program-files-base-vars.fd")
	meta := filepath.Join(dir, "program-files-base.json")

	if os.Getenv("SKADI_REBUILD_REFREEZE") == "1" {
		return fmt.Errorf("SKADI_REBUILD_REFREEZE=1 is forbidden; remove or relocate the prior golden explicitly")
	}
	for _, p := range []string{qcow, vars, meta} {
		if _, err := os.Stat(p); err == nil {
			return fmt.Errorf("refusing to overwrite existing golden artifact %s; remove or relocate the prior golden explicitly", p)
		} else if !os.IsNotExist(err) {
			return fmt.Errorf("inspect golden artifact %s: %w", p, err)
		}
	}
	if err := copyFile(g.disk, qcow, 0o444); err != nil {
		return err
	}
	if err := copyFile(g.vars, vars, 0o444); err != nil {
		return err
	}
	if h.manifest.Artifacts == nil {
		h.manifest.Artifacts = map[string]Artifact{}
	}
	for name, p := range map[string]string{
		"program-files-base.qcow2":   qcow,
		"program-files-base-vars.fd": vars,
	} {
		sum, err := sha256File(p)
		if err != nil {
			return fmt.Errorf("hash %s: %w", p, err)
		}
		h.manifest.Artifacts[name] = Artifact{Path: p, SHA256: sum, Mode: "0444"}
	}
	frozen := *h.manifest
	frozen.Snapshot = "freeze-time snapshot (pre-overlay-proof); authoritative record is evidence/report.json"
	if err := frozen.WriteJSON(meta); err != nil {
		return err
	}
	if err := os.Chmod(meta, 0o444); err != nil {
		return fmt.Errorf("chmod %s 0444: %w", meta, err)
	}
	sum, err := sha256File(meta)
	if err != nil {
		return fmt.Errorf("hash %s: %w", meta, err)
	}
	h.manifest.Artifacts["program-files-base.json"] = Artifact{Path: meta, SHA256: sum, Mode: "0444"}
	if home, herr := os.UserHomeDir(); herr == nil {
		compat := filepath.Join(home, ".cache", "skadi-vm")
		if compat != dir {
			if err := os.MkdirAll(compat, 0o755); err != nil {
				h.log.Printf("freeze: compat dir %s: %v", compat, err)
			} else {
				for name := range h.manifest.Artifacts {
					lp := filepath.Join(compat, name)
					if fi, err := os.Lstat(lp); err == nil && fi.Mode()&os.ModeSymlink == 0 {
						h.log.Printf("freeze: compat path %s is not a symlink; leaving it in place", lp)
						continue
					}
					_ = os.Remove(lp)
					if err := os.Symlink(filepath.Join(dir, name), lp); err != nil {
						h.log.Printf("freeze: compat symlink %s: %v", lp, err)
					}
				}
			}
		}
	}
	return nil
}

func (h *Harness) stageOverlayProof(ctx context.Context) error {
	base := filepath.Join(h.goldenDir, "program-files-base.qcow2")
	baseVars := filepath.Join(h.goldenDir, "program-files-base-vars.fd")
	beforeBase, err := sha256File(base)
	if err != nil {
		return fmt.Errorf("hash base before overlay: %w", err)
	}
	work := filepath.Join(h.guestWorkDir(), "overlay")
	if err := os.MkdirAll(work, 0o755); err != nil {
		return fmt.Errorf("create overlay work dir: %w", err)
	}
	overlay := filepath.Join(work, "overlay.qcow2")
	_ = os.Remove(overlay)
	res := h.runner.Run(ctx, CmdSpec{Name: "qemu-img", Args: []string{"create", "-f", "qcow2", "-F", "qcow2", "-b", base, overlay}}, nil)
	if res.Err != nil || res.ExitCode != 0 {
		return fmt.Errorf("create overlay qcow2 (exit %d): %w\n%s", res.ExitCode, res.Err, res.Combined)
	}
	vars := filepath.Join(work, "overlay-vars.fd")
	if err := copyFile(baseVars, vars, 0o600); err != nil {
		return err
	}
	g, err := h.newGuest("overlay", overlay, vars, filepath.Join(work, "overlay-serial.log"))
	if err != nil {
		return err
	}
	if err := g.boot(ctx, "cd", ""); err != nil {
		return err
	}
	h.guest = g
	if err := g.waitLogin(ctx); err != nil {
		return err
	}
	if err := g.waitSSH(ctx); err != nil {
		return err
	}
	if err := h.assertVarsWritable("overlay", g.vars); err != nil {
		return err
	}
	if err := h.assertGuestIdentity(ctx, "overlay"); err != nil {
		return err
	}
	if err := g.poweroff(ctx); err != nil {
		return err
	}
	if err := h.checkGuestDisk(ctx, "overlay", g); err != nil {
		return err
	}
	h.guest = nil
	afterBase, err := sha256File(base)
	if err != nil {
		return fmt.Errorf("hash base after overlay: %w", err)
	}
	baseUnchanged := beforeBase == afterBase
	h.manifest.BaseUntouched = boolPtr(baseUnchanged)
	if !baseUnchanged {
		return fmt.Errorf("golden base mutated during overlay proof: before=%s after=%s", beforeBase, afterBase)
	}
	for _, p := range []string{base, baseVars} {
		fi, err := os.Stat(p)
		if err != nil {
			return err
		}
		if fi.Mode().Perm() != 0o444 {
			return fmt.Errorf("golden artifact %s no longer 0444 (got %o)", p, fi.Mode().Perm())
		}
	}
	h.manifest.OverlayProof = boolPtr(true)
	return nil
}

func freePort() (int, error) {
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return 0, fmt.Errorf("allocate free port: %w", err)
	}
	defer l.Close()
	return l.Addr().(*net.TCPAddr).Port, nil
}

func tailFile(path string, n int) string {
	data, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	lines := strings.Split(strings.TrimRight(string(data), "\n"), "\n")
	if len(lines) > n {
		lines = lines[len(lines)-n:]
	}
	return strings.Join(lines, "\n")
}

func sha256File(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer f.Close()
	hsh := sha256.New()
	if _, err := io.Copy(hsh, f); err != nil {
		return "", err
	}
	return hex.EncodeToString(hsh.Sum(nil)), nil
}

func copyFile(src, dst string, mode os.FileMode) error {
	in, err := os.Open(src)
	if err != nil {
		return fmt.Errorf("open %s: %w", src, err)
	}
	defer in.Close()
	out, err := os.OpenFile(dst, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o600)
	if err != nil {
		return fmt.Errorf("create %s: %w", dst, err)
	}
	if _, err := io.Copy(out, in); err != nil {
		out.Close()
		return fmt.Errorf("copy %s -> %s: %w", src, dst, err)
	}
	if err := out.Close(); err != nil {
		return err
	}
	if err := os.Chmod(dst, mode); err != nil {
		return fmt.Errorf("chmod %s: %w", dst, err)
	}
	return nil
}

func shellSingleQuote(s string) string {
	return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'"
}

func firstTwoFields(s string) string {
	f := strings.Fields(strings.TrimSpace(s))
	if len(f) < 2 {
		return ""
	}
	return f[0] + " " + f[1]
}

func lastNonEmpty(s string) string {
	var last string
	for _, ln := range strings.Split(s, "\n") {
		if t := strings.TrimSpace(ln); t != "" {
			last = t
		}
	}
	return last
}

func diskoScriptPath(stdout string) (string, error) {
	paths := storePathLines(stdout)
	switch len(paths) {
	case 0:
		return "", fmt.Errorf("disko --dry-run printed no /nix/store script path")
	case 1:
		return paths[0], nil
	}
	var disko []string
	for _, p := range paths {
		if strings.Contains(filepath.Base(p), "disko") {
			disko = append(disko, p)
		}
	}
	if len(disko) != 1 {
		return "", fmt.Errorf("cannot isolate exactly one disko script path among %v", paths)
	}
	return disko[0], nil
}
