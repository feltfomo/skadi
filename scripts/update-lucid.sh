#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

LUCID_NIX="modules/_pkgs/lucid.nix"
LOCKFILE="modules/_pkgs/package-lock.json"
GITLAB_API="https://gitlab.com/api/v4/projects/sanoojes%2Fspicetify-lucid/repository/commits?ref_name=main&per_page=1"

# get latest commit from gitlab
log_info "Fetching latest Lucid commit from GitLab..."
LATEST_REV=$(curl -sL "$GITLAB_API" | jq -r '.[0].id')

if [[ -z "$LATEST_REV" || "$LATEST_REV" == "null" ]]; then
    log_error "Failed to fetch latest commit from GitLab"
    exit 1
fi

log_info "Latest commit: $LATEST_REV"

# skip if already up to date
CURRENT_REV=$(grep 'rev = ' "$LUCID_NIX" 2>/dev/null | head -1 | grep -oP '"[^"]+"' | tr -d '"' || true)

if [[ "$CURRENT_REV" == "$LATEST_REV" ]]; then
    log_info "Already at latest commit ($LATEST_REV). Nothing to do."
    exit 0
fi

log_warn "Update available: $CURRENT_REV → $LATEST_REV"

# prefetch new source hash
log_info "Prefetching source hash..."
TARBALL_URL="https://gitlab.com/sanoojes/spicetify-lucid/-/archive/${LATEST_REV}/spicetify-lucid-${LATEST_REV}.tar.gz"
RAW_HASH=$(nix-prefetch-url --unpack "$TARBALL_URL" 2>/dev/null)
NEW_SRC_HASH=$(nix-hash --to-sri --type sha256 "$RAW_HASH")
log_info "New source hash: $NEW_SRC_HASH"

# regenerate package-lock.json from new source
log_info "Regenerating package-lock.json..."
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

curl -sL "$TARBALL_URL" | tar -xz -C "$WORKDIR" --strip-components=1

pushd "$WORKDIR" > /dev/null
npm install --ignore-scripts 2>/dev/null
popd > /dev/null

cp "$WORKDIR/package-lock.json" "$LOCKFILE"
log_info "package-lock.json updated"

# prefetch new npmDepsHash
log_info "Prefetching npm deps hash..."
NEW_NPM_HASH=$(prefetch-npm-deps "$LOCKFILE" 2>/dev/null)
log_info "New npmDepsHash: $NEW_NPM_HASH"

# patch lucid.nix
log_info "Patching lucid.nix..."
CURRENT_SRC_HASH=$(grep 'hash = ' "$LUCID_NIX" | head -1 | grep -oP '"sha256-[^"]+"' | tr -d '"')
CURRENT_NPM_HASH=$(grep 'npmDepsHash' "$LUCID_NIX" | grep -oP '"sha256-[^"]+"' | tr -d '"')

sed -i "s|$CURRENT_SRC_HASH|$NEW_SRC_HASH|g" "$LUCID_NIX"
sed -i "s|$CURRENT_NPM_HASH|$NEW_NPM_HASH|g" "$LUCID_NIX"
sed -i "s|rev = \"[^\"]*\";|rev = \"$LATEST_REV\";|" "$LUCID_NIX"

log_info "lucid.nix patched"

# summary
echo ""
log_info "Done! Changes:"
echo "  rev:         $CURRENT_REV → $LATEST_REV"
echo "  src hash:    $CURRENT_SRC_HASH → $NEW_SRC_HASH"
echo "  npmDepsHash: $CURRENT_NPM_HASH → $NEW_NPM_HASH"
