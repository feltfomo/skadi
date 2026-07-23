// Package harness implements the rebuild-vm-golden supervision core: pure
// output scanners, a cancelable command runner, the per-rev signed cache, the
// run manifest, and the fail-closed state machine. Standard library only.
package harness

import (
	"bufio"
	"regexp"
	"strings"
)

// Nix / Lix build-plan grammar. These markers are what the build-count safety
// invariant keys on. They are currently tuned against the synthetic fixtures
// under testdata/; revalidate them byte-for-byte against real captured
// d33f37a5 build output before trusting the gate.
var (
	// "these N derivations will be built:" or "this derivation will be built:".
	reWillBeBuiltHeader = regexp.MustCompile(`^\s*(?:these\s+\d+\s+derivations|this\s+derivation)\s+will\s+be\s+built:`)
	// "building '/nix/store/....drv'..." printed when a build actually starts.
	reBuildingDrv = regexp.MustCompile(`building '(/nix/store/[^']+\.drv)(?:,[^']*)?'`)
	// An indented store .drv path listed under a "will be built:" header.
	reStoreDrvLine = regexp.MustCompile(`^\s+(/nix/store/\S+\.drv)\b`)
	// Substitution: "copying path '/nix/store/...' from '...'".
	reCopyingPath = regexp.MustCompile(`copying path '(/nix/store/[^']+)' from '([^']*)'`)
	// "these N paths will be fetched (…):" or "this path will be fetched (…):".
	// A store-isolated dry-run against an empty chroot store lists everything it
	// would substitute here; a non-empty set proves the signed cache was actually
	// exercised rather than a warm local store answering 0/0.
	reWillBeFetchedHeader = regexp.MustCompile(`^\s*(?:these\s+\d+\s+paths|this\s+path)\s+will\s+be\s+fetched\b`)
	// A store output path (no .drv) listed under a "will be fetched:" header.
	reStoreOutLine = regexp.MustCompile(`^\s+(/nix/store/\S+)\s*$`)
)

// BuildPlan is the parsed result of nix build / dry-run output.
type BuildPlan struct {
	WillBuild []string // unique drvPaths that will be or are being built
	Building  []string // drvPaths that actually started building
	Copied    []string // store paths substituted from a binary cache
	WillFetch []string // store paths a dry-run reports it would substitute
}

// ScanBuildPlan parses combined nix output into a BuildPlan. It is pure and
// deterministic; first-appearance order is preserved.
func ScanBuildPlan(output string) BuildPlan {
	var p BuildPlan
	seen := map[string]bool{}
	addWill := func(drv string) {
		if drv == "" || seen[drv] {
			return
		}
		seen[drv] = true
		p.WillBuild = append(p.WillBuild, drv)
	}
	sc := bufio.NewScanner(strings.NewReader(output))
	sc.Buffer(make([]byte, 0, 64*1024), 8*1024*1024)
	seenFetch := map[string]bool{}
	addFetch := func(path string) {
		if path == "" || seenFetch[path] {
			return
		}
		seenFetch[path] = true
		p.WillFetch = append(p.WillFetch, path)
	}
	inWillBlock := false
	inFetchBlock := false
	for sc.Scan() {
		line := sc.Text()
		if reWillBeBuiltHeader.MatchString(line) {
			inWillBlock = true
			inFetchBlock = false
			continue
		}
		if reWillBeFetchedHeader.MatchString(line) {
			inFetchBlock = true
			inWillBlock = false
			continue
		}
		if inWillBlock {
			if m := reStoreDrvLine.FindStringSubmatch(line); m != nil {
				addWill(m[1])
				continue
			}
			inWillBlock = false
		}
		if inFetchBlock {
			if m := reStoreOutLine.FindStringSubmatch(line); m != nil {
				addFetch(m[1])
				continue
			}
			inFetchBlock = false
		}
		if m := reBuildingDrv.FindStringSubmatch(line); m != nil {
			p.Building = append(p.Building, m[1])
			addWill(m[1])
		}
		if m := reCopyingPath.FindStringSubmatch(line); m != nil {
			p.Copied = append(p.Copied, m[1])
		}
	}
	return p
}

// BuildCount is the number of unique derivations the plan will build. The core
// safety invariant requires this to be 0 for a cached gate.
func (p BuildPlan) BuildCount() int { return len(p.WillBuild) }

// IsClean reports whether nothing will be built.
func (p BuildPlan) IsClean() bool { return len(p.WillBuild) == 0 }

// FetchCount is the number of unique store paths the plan would substitute,
// counting both a dry-run's "will be fetched" listing and any realized "copying
// path" lines. A store-isolated cached gate requires this to be > 0: against an
// empty chroot store, build==0 && fetch==0 means the plan never touched the
// signed cache and must fail closed rather than pass vacuously.
func (p BuildPlan) FetchCount() int {
	seen := map[string]bool{}
	n := 0
	for _, s := range p.WillFetch {
		if !seen[s] {
			seen[s] = true
			n++
		}
	}
	for _, s := range p.Copied {
		if !seen[s] {
			seen[s] = true
			n++
		}
	}
	return n
}

// BuildLineViolation returns a non-empty description if a single line indicates
// a derivation will be or is being built. It is the per-line hook the live
// emergency stop uses so a build is killed the instant it is announced, without
// waiting for the command to exit.
func BuildLineViolation(line string) string {
	if m := reBuildingDrv.FindStringSubmatch(line); m != nil {
		return m[1]
	}
	if m := reStoreDrvLine.FindStringSubmatch(line); m != nil {
		return m[1]
	}
	if reWillBeBuiltHeader.MatchString(line) {
		return strings.TrimSpace(line)
	}
	return ""
}

// NormalizePubKey canonicalizes a Nix binary-cache public key of the form
// "name:base64blob", trimming whitespace and splitting into its algorithm name
// and key blob. ok is false if the shape is invalid.
func NormalizePubKey(s string) (name, key string, ok bool) {
	s = strings.TrimSpace(s)
	i := strings.IndexByte(s, ':')
	if i <= 0 || i >= len(s)-1 {
		return "", "", false
	}
	return s[:i], s[i+1:], true
}

// SameDrv compares two derivation paths for equality after trimming whitespace.
func SameDrv(a, b string) bool { return strings.TrimSpace(a) == strings.TrimSpace(b) }
