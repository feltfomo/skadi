package harness

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func readFixture(t *testing.T, name string) string {
	t.Helper()
	b, err := os.ReadFile(filepath.Join("testdata", name))
	if err != nil {
		t.Fatalf("read fixture %s: %v", name, err)
	}
	return string(b)
}

func TestScanBuildPlanGreenIsClean(t *testing.T) {
	p := ScanBuildPlan(readFixture(t, "green_zero_build.log"))
	if !p.IsClean() {
		t.Fatalf("expected clean plan, got WillBuild=%v", p.WillBuild)
	}
	if p.BuildCount() != 0 {
		t.Fatalf("expected build count 0, got %d", p.BuildCount())
	}
	if len(p.Copied) == 0 {
		t.Fatal("expected substituted (copied) paths in a green run, got none")
	}
}

func TestScanBuildPlanFailedCountsBuilds(t *testing.T) {
	p := ScanBuildPlan(readFixture(t, "failed_will_be_built.log"))
	if p.IsClean() {
		t.Fatal("expected a non-clean plan for the failed fixture")
	}
	if p.BuildCount() != 2 {
		t.Fatalf("expected 2 derivations to build, got %d (%v)", p.BuildCount(), p.WillBuild)
	}
	if len(p.Building) != 1 {
		t.Fatalf("expected 1 building line, got %d", len(p.Building))
	}
}

func TestBuildLineViolation(t *testing.T) {
	cases := map[string]bool{
		`building '/nix/store/aaaa1111bbbb2222cccc3333dddd4444-skadi-install.drv'...`: true,
		`  /nix/store/eeee5555ffff6666gggg7777hhhh8888-nixos-system-vm.drv`:           true,
		`these 3 derivations will be built:`:                                          true,
		`copying path '/nix/store/xxxx-etc' from 'https://cache.nixos.org'...`:        false,
		`/nix/store/zzzz-nixos-system-vm-26.05`:                                       false,
	}
	for line, want := range cases {
		if got := BuildLineViolation(line) != ""; got != want {
			t.Errorf("BuildLineViolation(%q)=%v, want %v", line, got, want)
		}
	}
}

func TestNormalizePubKey(t *testing.T) {
	name, key, ok := NormalizePubKey("  skadi-1:abc123==  ")
	if !ok || name != "skadi-1" || key != "abc123==" {
		t.Fatalf("got name=%q key=%q ok=%v", name, key, ok)
	}
	if _, _, ok := NormalizePubKey("noseparator"); ok {
		t.Fatal("expected failure on missing separator")
	}
}

func TestScanBuildPlanFetchCount(t *testing.T) {
	out := strings.Join([]string{
		"these 2 paths will be fetched (1.23 MiB download, 4.56 MiB unpacked):",
		"  /nix/store/aaaa-foo",
		"  /nix/store/bbbb-bar",
		"warning: nothing to build",
	}, "\n")
	p := ScanBuildPlan(out)
	if p.BuildCount() != 0 {
		t.Fatalf("expected 0 builds, got %d (%v)", p.BuildCount(), p.WillBuild)
	}
	if p.FetchCount() != 2 {
		t.Fatalf("expected fetch count 2, got %d (%v)", p.FetchCount(), p.WillFetch)
	}
}
