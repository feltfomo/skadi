package harness

import (
	"encoding/json"
	"fmt"
	"os"
	"sort"
	"strings"
	"time"
)

// StageRecord is the recorded outcome of one state-machine stage.
type StageRecord struct {
	Name    string        `json:"name"`
	Status  string        `json:"status"` // "pass" or "failed"
	Err     string        `json:"error,omitempty"`
	Elapsed time.Duration `json:"elapsed_ns"`
}

// IdentityProof records a fixed VM identity fingerprint observed during verify.
type IdentityProof struct {
	Name     string `json:"name"`
	Expected string `json:"expected"`
	Observed string `json:"observed"`
	Match    bool   `json:"match"`
}

// SecretProof records that a decrypted secret matched its fixture plaintext.
type SecretProof struct {
	Name  string `json:"name"`
	Match bool   `json:"match"`
}

// Artifact records a frozen golden file: its path, content hash, and octal mode
// as published (the golden qcow2/vars/metadata are frozen 0444).
type Artifact struct {
	Path   string `json:"path"`
	SHA256 string `json:"sha256"`
	Mode   string `json:"mode"`
}

// Manifest is the machine-readable record of one rebuild run. It is written as
// JSON and rendered to a human-readable text report; nothing is published to
// Notion.
type Manifest struct {
	Rev                   string              `json:"rev"`
	ApprovedRev           string              `json:"approved_rev,omitempty"`
	Subcommand            string              `json:"subcommand"`
	Host                  string              `json:"host"`
	StartedAt             time.Time           `json:"started_at"`
	FinishedAt            time.Time           `json:"finished_at,omitempty"`
	FinalStage            string              `json:"final_stage"`
	Status                string              `json:"status"`
	CacheKey              string              `json:"cache_key,omitempty"`
	PublicKey             string              `json:"public_key,omitempty"`
	PreparedSourcePath    string              `json:"prepared_source_path,omitempty"`
	PreparedSourceHash    string              `json:"prepared_source_hash,omitempty"`
	PreparedSourceStatus  string              `json:"prepared_source_status,omitempty"`
	VMIdentityRecipient   string              `json:"vm_identity_recipient,omitempty"`
	VMIdentityFingerprint string              `json:"vm_identity_fingerprint,omitempty"`
	VMFixtureSHA256       string              `json:"vm_fixture_sha256,omitempty"`
	DrvPaths              map[string]string   `json:"drv_paths,omitempty"`
	StorePaths            map[string]string   `json:"store_paths,omitempty"`
	LiveBuildCount        int                 `json:"live_build_count"`
	FetchCount            int                 `json:"fetch_count"`
	Identity              []IdentityProof     `json:"identity,omitempty"`
	Secrets               []SecretProof       `json:"secrets,omitempty"`
	GoldenDir             string              `json:"golden_dir,omitempty"`
	Artifacts             map[string]Artifact `json:"artifacts,omitempty"`
	InstallLogSHA256      string              `json:"install_log_sha256,omitempty"`
	FirstBootSerialSHA256 string              `json:"first_boot_serial_sha256,omitempty"`
	SourceTarballSHA256   string              `json:"source_tarball_sha256,omitempty"`
	Snapshot              string              `json:"snapshot,omitempty"`
	OverlayProof          bool                `json:"overlay_proof"`
	BaseUntouched         bool                `json:"base_untouched"`
	Stages                []StageRecord       `json:"stages,omitempty"`
}

// WriteJSON writes the manifest as indented JSON to path.
func (m *Manifest) WriteJSON(path string) error {
	b, err := json.MarshalIndent(m, "", "  ")
	if err != nil {
		return fmt.Errorf("marshal manifest: %w", err)
	}
	b = append(b, '\n')
	if err := os.WriteFile(path, b, 0o644); err != nil {
		return fmt.Errorf("write manifest json: %w", err)
	}
	return nil
}

// WriteHuman renders a readable summary to path.
func (m *Manifest) WriteHuman(path string) error {
	return os.WriteFile(path, []byte(m.Human()), 0o644)
}

// Human renders the manifest as a plain-text report.
func (m *Manifest) Human() string {
	var b strings.Builder
	fmt.Fprintf(&b, "rebuild-vm-golden report\n")
	fmt.Fprintf(&b, "========================\n")
	fmt.Fprintf(&b, "rev:         %s\n", m.Rev)
	if m.ApprovedRev != "" {
		fmt.Fprintf(&b, "approved:    %s\n", m.ApprovedRev)
	}
	fmt.Fprintf(&b, "subcommand:  %s\n", m.Subcommand)
	fmt.Fprintf(&b, "host:        %s\n", m.Host)
	fmt.Fprintf(&b, "status:      %s\n", m.Status)
	fmt.Fprintf(&b, "final stage: %s\n", m.FinalStage)
	fmt.Fprintf(&b, "started:     %s\n", m.StartedAt.Format(time.RFC3339))
	if !m.FinishedAt.IsZero() {
		fmt.Fprintf(&b, "finished:    %s\n", m.FinishedAt.Format(time.RFC3339))
	}
	fmt.Fprintf(&b, "build count: %d\n", m.LiveBuildCount)
	fmt.Fprintf(&b, "fetch count: %d\n", m.FetchCount)
	if m.PreparedSourcePath != "" {
		fmt.Fprintf(&b, "prepared src: %s\n", m.PreparedSourcePath)
	}
	if m.PreparedSourceHash != "" {
		fmt.Fprintf(&b, "prepared sha: %s\n", m.PreparedSourceHash)
	}
	if m.PreparedSourceStatus != "" {
		fmt.Fprintf(&b, "prepared status: %s\n", m.PreparedSourceStatus)
	}
	if m.VMIdentityFingerprint != "" {
		fmt.Fprintf(&b, "vm identity: %s\n", m.VMIdentityFingerprint)
	}
	if m.VMIdentityRecipient != "" {
		fmt.Fprintf(&b, "vm recipient: %s\n", m.VMIdentityRecipient)
	}
	if m.VMFixtureSHA256 != "" {
		fmt.Fprintf(&b, "vm fixture sha256: %s\n", m.VMFixtureSHA256)
	}
	if m.CacheKey != "" {
		fmt.Fprintf(&b, "cache key:   %s\n", m.CacheKey)
	}
	if m.PublicKey != "" {
		fmt.Fprintf(&b, "public key:  %s\n", m.PublicKey)
	}
	if len(m.DrvPaths) > 0 {
		b.WriteString("\nderivations:\n")
		for _, k := range sortedKeys(m.DrvPaths) {
			fmt.Fprintf(&b, "  %-12s %s\n", k+":", m.DrvPaths[k])
		}
	}
	if len(m.StorePaths) > 0 {
		b.WriteString("\nstore paths:\n")
		for _, k := range sortedKeys(m.StorePaths) {
			fmt.Fprintf(&b, "  %-12s %s\n", k+":", m.StorePaths[k])
		}
	}
	if len(m.Identity) > 0 {
		b.WriteString("\nidentity:\n")
		for _, id := range m.Identity {
			fmt.Fprintf(&b, "  [%s] %s expected=%s observed=%s\n", mark(id.Match), id.Name, id.Expected, id.Observed)
		}
	}
	if len(m.Secrets) > 0 {
		b.WriteString("\nsecrets:\n")
		for _, s := range m.Secrets {
			fmt.Fprintf(&b, "  [%s] %s\n", mark(s.Match), s.Name)
		}
	}
	if m.GoldenDir != "" {
		fmt.Fprintf(&b, "\ngolden dir:  %s\n", m.GoldenDir)
	}
	if len(m.Artifacts) > 0 {
		b.WriteString("\nfrozen artifacts:\n")
		for _, k := range sortedArtifactKeys(m.Artifacts) {
			a := m.Artifacts[k]
			fmt.Fprintf(&b, "  %-26s mode=%s sha256=%s %s\n", k+":", a.Mode, a.SHA256, a.Path)
		}
		fmt.Fprintf(&b, "overlay proof:  %s\n", mark(m.OverlayProof))
		fmt.Fprintf(&b, "base untouched: %s\n", mark(m.BaseUntouched))
	}
	if m.InstallLogSHA256 != "" {
		fmt.Fprintf(&b, "install-log sha256:       %s\n", m.InstallLogSHA256)
	}
	if m.FirstBootSerialSHA256 != "" {
		fmt.Fprintf(&b, "first-boot serial sha256: %s\n", m.FirstBootSerialSHA256)
	}
	if m.SourceTarballSHA256 != "" {
		fmt.Fprintf(&b, "source tarball sha256:    %s\n", m.SourceTarballSHA256)
	}
	if len(m.Stages) > 0 {
		b.WriteString("\nstages:\n")
		for _, st := range m.Stages {
			line := fmt.Sprintf("  %-22s %s", st.Name, st.Status)
			if st.Err != "" {
				line += " - " + st.Err
			}
			b.WriteString(line + "\n")
		}
	}
	return b.String()
}

func mark(ok bool) string {
	if ok {
		return "OK"
	}
	return "XX"
}

func sortedKeys(m map[string]string) []string {
	ks := make([]string, 0, len(m))
	for k := range m {
		ks = append(ks, k)
	}
	sort.Strings(ks)
	return ks
}

func sortedArtifactKeys(m map[string]Artifact) []string {
	ks := make([]string, 0, len(m))
	for k := range m {
		ks = append(ks, k)
	}
	sort.Strings(ks)
	return ks
}
