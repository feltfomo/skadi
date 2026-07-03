#!/usr/bin/env bash
# skadi-install <host>  -- two-phase reinstall, run from the skadi installer ISO.
#   1. disko format+mount   2. host key + sops secrets into /persist
#   3. nixos-install
#
# Home repos (Wallpapers + notion-sync mappings) are cloned on first boot by the
# bootstrap-repos aspect, not here -- so this stays a pure OS bootstrapper.
#
# NEVER run against a booted skadi system -- disko repartitions. Guarded below.
# set -euo pipefail is injected by writeShellApplication.

SKADI_REMOTE="https://github.com/feltfomo/skadi"

MNT=/mnt
WORK=/tmp/skadi-install

log()  { printf '\033[0;32m[skadi-install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[skadi-install]\033[0m %s\n' "$*"; }
die()  { printf '\033[0;31m[skadi-install]\033[0m %s\n' "$*" >&2; exit 1; }

HOST="${1:-}"
[ -n "$HOST" ] || die "usage: skadi-install <host>   (e.g. skadi-install khion)"

# guard: refuse to run on a booted skadi install (disko would repartition it).
if [ ! -d /iso ] && [ -e /persist/etc/skadi ]; then
  die "this looks like a booted skadi system, not the ISO -- refusing to repartition."
fi

# 0. clone the flake we install from (writable tree with .git for notion-sync).
rm -rf "$WORK"
log "cloning skadi from $SKADI_REMOTE"
git clone "$SKADI_REMOTE" "$WORK"
cd "$WORK"
test -f "modules/hosts/${HOST}.nix" || die "unknown host '$HOST' (no modules/hosts/${HOST}.nix)"

# 1. disko: destroy + format + mount at /mnt.
#    (older disko: swap the mode for `--mode disko`.)
lsblk
warn "about to DESTROY and repartition the disk in modules/hosts/_${HOST}/disko.nix"
read -r -p "type '$HOST' to confirm: " confirm
[ "$confirm" = "$HOST" ] || die "aborted"
log "running disko (destroy,format,mount)"
disko --mode destroy,format,mount --flake ".#${HOST}"

# 2. host keys -> /persist, derive age recipient, rewrite .sops.yaml.
install -d -m0755 "$MNT/persist/etc/ssh"
log "generating host SSH keys into /persist/etc/ssh"
ssh-keygen -t ed25519 -N "" -C "root@${HOST}" -f "$MNT/persist/etc/ssh/ssh_host_ed25519_key"
ssh-keygen -t rsa -b 4096 -N "" -C "root@${HOST}" -f "$MNT/persist/etc/ssh/ssh_host_rsa_key"
chmod 600 "$MNT"/persist/etc/ssh/*_key
chmod 644 "$MNT"/persist/etc/ssh/*_key.pub

log "deriving age recipient from the new host key"
AGE_RECIP="$(ssh-to-age -i "$MNT/persist/etc/ssh/ssh_host_ed25519_key.pub")"
[ -n "$AGE_RECIP" ] || die "ssh-to-age produced no recipient"
log "age recipient: $AGE_RECIP"
cat > .sops.yaml <<EOF
creation_rules:
  - path_regex: secrets/secrets.yaml\$
    age: $AGE_RECIP
EOF

# 3. provision secrets: password hash (mkpasswd) + token + placeholders.
log "set the login password for feltfomo"
PW_HASH="$(mkpasswd -m sha-512)"
NOTION_LINE="NOTION_TOKEN=REPLACE_ME"
read -r -p "paste NOTION_TOKEN (ntn_...) or leave blank for placeholder: " ntn
[ -n "$ntn" ] && NOTION_LINE="NOTION_TOKEN=$ntn"

install -d -m0755 secrets
cat > secrets/secrets.yaml <<EOF
feltfomo-password: "$PW_HASH"
notion-token: "$NOTION_LINE"
hermes-secrets: "GROQ_API_KEY=REPLACE_ME"
EOF
log "encrypting secrets/secrets.yaml to $AGE_RECIP"
sops --encrypt --in-place secrets/secrets.yaml
git add -A .sops.yaml secrets/secrets.yaml

# 4. copy flake to /persist/etc/skadi (impermanence-persisted) and install.
install -d -m0755 "$MNT/persist/etc"
rm -rf "$MNT/persist/etc/skadi"
cp -a "$WORK" "$MNT/persist/etc/skadi"
log "nixos-install --flake .#$HOST"
nixos-install --flake "${WORK}#${HOST}" --no-root-passwd

log "OS install done. home repos clone themselves on first boot (bootstrap-repos)."
log "reboot into $HOST, confirm login on a fresh tty, then run"
log "'tailscale funnel --bg 8080' once for notion-sync webhooks."
