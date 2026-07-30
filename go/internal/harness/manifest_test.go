package harness

import (
	"encoding/json"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestManifestJSONRoundTrip(t *testing.T) {
	m := &Manifest{
		Rev:        "d33f37a5",
		Subcommand: "all",
		Host:       "vm",
		StartedAt:  time.Unix(1700000000, 0).UTC(),
		FinalStage: "finalize",
		Status:     "complete",
		DrvPaths:   map[string]string{"toplevel": "/nix/store/x.drv"},
		Stages:     []StageRecord{{Name: "preflight", Status: "pass"}},
	}
	b, err := json.Marshal(m)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	var got Manifest
	if err := json.Unmarshal(b, &got); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if got.Rev != m.Rev || got.Status != m.Status || got.FinalStage != m.FinalStage {
		t.Fatalf("round-trip mismatch: %+v", got)
	}
	if got.DrvPaths["toplevel"] != "/nix/store/x.drv" {
		t.Fatalf("drv paths lost: %+v", got.DrvPaths)
	}
	if len(got.Stages) != 1 || got.Stages[0].Name != "preflight" {
		t.Fatalf("stages lost: %+v", got.Stages)
	}
}

func TestManifestWriteFiles(t *testing.T) {
	m := &Manifest{Rev: "d33f37a5", Status: "complete", FinalStage: "finalize"}
	dir := t.TempDir()
	if err := m.WriteJSON(filepath.Join(dir, "report.json")); err != nil {
		t.Fatalf("write json: %v", err)
	}
	if err := m.WriteHuman(filepath.Join(dir, "report.txt")); err != nil {
		t.Fatalf("write human: %v", err)
	}
	h := m.Human()
	if !strings.Contains(h, "rebuild-vm-golden report") {
		t.Fatal("human report missing header")
	}
	if strings.Contains(h, "build count") || strings.Contains(h, "fetch count") {
		t.Fatal("human report invented unobserved counts")
	}
	b, err := json.Marshal(m)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(b), "gate_build_count") || strings.Contains(string(b), "gate_fetch_count") || strings.Contains(string(b), "overlay_proof") || strings.Contains(string(b), "base_untouched") {
		t.Fatalf("json invented unobserved measurements: %s", b)
	}
}

func TestManifestEmitsFreshPreparedSourceProvenance(t *testing.T) {
	m := &Manifest{
		PreparedSourcePath:   "/evidence/fresh/prepared-source",
		PreparedSourceReused: boolPtr(false),
	}
	b, err := json.Marshal(m)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(b), `"prepared_source_reused":false`) {
		t.Fatalf("json omitted fresh prepared-source provenance: %s", b)
	}
	if !strings.Contains(m.Human(), "prepared reused: false") {
		t.Fatalf("human report omitted fresh prepared-source provenance:\n%s", m.Human())
	}
}

func TestManifestEmitsObservedMeasurements(t *testing.T) {
	m := &Manifest{
		PreparedSourcePath:   "/evidence/build-cache/prepared-source",
		PreparedSourceReused: boolPtr(true),
		PreparedSourceOrigin: "/evidence/build-cache",
		GateBuildCount:       intPtr(0),
		GateFetchCount:       intPtr(9),
		ProvisionBuildCount:  intPtr(0),
		OverlayProof:         boolPtr(true),
		BaseUntouched:        boolPtr(true),
		Identity:             []IdentityProof{{Name: "host", Expected: "vm", Observed: "vm", Match: true}},
		Secrets:              []SecretProof{{Name: "notion-token", SHA256: "abc", Match: true}},
	}
	b, err := json.Marshal(m)
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{"\"prepared_source_reused\":true", "\"prepared_source_origin_run\":\"/evidence/build-cache\"", "\"gate_build_count\":0", "\"gate_fetch_count\":9", "\"provision_build_count\":0", "\"overlay_proof\":true", "\"base_untouched\":true", "\"sha256\":\"abc\""} {
		if !strings.Contains(string(b), want) {
			t.Fatalf("json missing %s: %s", want, b)
		}
	}
	h := m.Human()
	for _, want := range []string{"prepared reused: true", "prepared origin run: /evidence/build-cache", "gate build count: 0", "gate fetch count: 9", "provision build count: 0", "sha256=abc"} {
		if !strings.Contains(h, want) {
			t.Fatalf("human report missing %q:\n%s", want, h)
		}
	}
}
