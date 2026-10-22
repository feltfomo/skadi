set -euo pipefail

checkout="$1"
repository="$2"

if [ -e "$checkout" ] || [ -L "$checkout" ]; then
  if [ -L "$checkout" ] || [ ! -d "$checkout/.git" ]; then
    printf 'bootstrap-skills: refusing an existing path without its own checkout: %s\n' "$checkout" >&2
    exit 1
  fi
  root="$(git -C "$checkout" rev-parse --show-toplevel)"
  if [ "$root" != "$checkout" ]; then
    printf 'bootstrap-skills: refusing a different checkout root: %s\n' "$root" >&2
    exit 1
  fi
  exit 0
fi

mkdir -p -- "$(dirname -- "$checkout")"
git clone -- "$repository" "$checkout"
