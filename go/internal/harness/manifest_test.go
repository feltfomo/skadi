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
	m := &Manifest{Rev: "d33f37a5", Status: "complete", FinalStage: "finalize", LiveBuildCount: 0}
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
	if !strings.Contains(h, "build count: 0") {
		t.Fatal("human report missing build count")
	}
}
