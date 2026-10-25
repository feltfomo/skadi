import argparse
import fcntl
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
import time

import tomlkit


def write_atomic(path, contents):
    with tempfile.NamedTemporaryFile(dir=path.parent, prefix=".history-", delete=False) as stream:
        stream.write(contents)
        stream.flush()
        os.fsync(stream.fileno())
        temporary = Path(stream.name)
    os.replace(temporary, path)


def load_launcher_history(path, filename):
    try:
        data = json.loads(path.read_text())
        if not isinstance(data, dict):
            raise ValueError("expected provider records")
        for records in data.values():
            if filename == "recently_used.json":
                valid = isinstance(records, list) and all(isinstance(item, str) for item in records)
            else:
                valid = isinstance(records, dict) and all(
                    type(count) is int and count >= 0 for count in records.values()
                )
            if not valid:
                raise ValueError("invalid provider record")
        return data
    except (ValueError, UnicodeError) as error:
        print(f"Noctalia history retained in backup but skipped: {path}: {error}", file=sys.stderr)
        return {}


def migrate_history(state):
    shared = state / "noctalia"
    shared.mkdir(mode=0o700, parents=True, exist_ok=True)
    with (shared / ".history-migration.lock").open("a") as lock:
        os.chmod(lock.name, 0o600)
        fcntl.flock(lock, fcntl.LOCK_EX)
        marker = shared / ".shared-history"
        if marker.exists():
            return
        sources = {
            "hyprland": shared / "profiles/hyprland/noctalia",
            "mangowm": shared / "profiles/mangowm/noctalia",
            "shared": shared,
        }
        backups = shared / "history-backups"
        backups.mkdir(mode=0o700, exist_ok=True)
        archive = backups / str(time.time_ns())
        archive.mkdir(mode=0o700)
        for filename in ("recently_used.json", "usage_counts.json"):
            paths = []
            for name, directory in sources.items():
                path = directory / filename
                if path.exists():
                    destination = archive / name
                    destination.mkdir(mode=0o700, exist_ok=True)
                    shutil.copy2(path, destination / filename)
                    paths.append(path)
            merged = {}
            for path in sorted(paths, key=lambda item: item.stat().st_mtime_ns, reverse=True):
                for provider, records in load_launcher_history(path, filename).items():
                    if filename == "recently_used.json":
                        recent = merged.setdefault(provider, [])
                        seen = set(recent)
                        for item in records:
                            if item not in seen and len(recent) < 20:
                                recent.append(item)
                                seen.add(item)
                    else:
                        counts = merged.setdefault(provider, {})
                        # Profiles may contain copies of the same history; summing double-counts them.
                        for item, count in records.items():
                            counts[item] = max(counts.get(item, 0), count)
            if merged:
                write_atomic(shared / filename, (json.dumps(merged, indent=2) + "\n").encode())

        candidates = []
        for directory in sources.values():
            clipboard = directory / "clipboard"
            manifests = [clipboard / name for name in ("index.json", "index.enc")]
            manifests = [path for path in manifests if path.is_file() and path.stat().st_size > 0]
            if manifests and (clipboard / "entries").is_dir():
                candidates.append((max(path.stat().st_mtime_ns for path in manifests), clipboard))
        if candidates:
            _, newest = max(candidates, key=lambda item: item[0])
            destination = shared / "clipboard"
            if newest != destination:
                # An encrypted index and its payloads must move as one store.
                with tempfile.TemporaryDirectory(dir=shared, prefix=".clipboard-") as staging:
                    prepared = Path(staging) / "clipboard"
                    shutil.copytree(newest, prepared)
                    if destination.exists():
                        destination.rename(archive / "clipboard")
                    prepared.rename(destination)
        write_atomic(marker, b"shared launcher and clipboard history\n")


def prune_equal(overrides, defaults):
    for key in list(overrides):
        if key not in defaults:
            continue
        if isinstance(overrides[key], dict) and isinstance(defaults[key], dict):
            prune_equal(overrides[key], defaults[key])
            if not overrides[key]:
                del overrides[key]
        elif overrides[key] == defaults[key]:
            del overrides[key]


def remove_disabled_widgets(settings, defaults):
    enabled = set(settings.get("plugins", {}).get("enabled", defaults["plugins"]["enabled"]))
    widgets = settings.get("widget", {})
    disabled = set()
    for name, widget in list(widgets.items()):
        kind = widget.get("type", "")
        if "/" in kind and kind.split(":")[0] not in enabled:
            disabled.add(name)
            del widgets[name]
    for bar in settings.get("bar", {}).values():
        for position in ("start", "center", "end"):
            if position in bar:
                bar[position] = [name for name in bar[position] if name not in disabled]
    desktop = settings.get("desktop_widgets", {})
    for name, widget in list(desktop.get("widget", {}).items()):
        kind = widget.get("type", "")
        if "/" in kind and kind.split(":")[0] not in enabled:
            del desktop["widget"][name]
            if "widget_order" in desktop:
                desktop["widget_order"] = [item for item in desktop["widget_order"] if item != name]


def reconcile(path, defaults):
    if not path.exists():
        return
    before = path.read_bytes()
    settings = tomlkit.parse(before.decode())
    remove_disabled_widgets(settings, defaults)
    prune_equal(settings, defaults)
    if tomlkit.parse(before.decode()) == settings:
        return
    backups = path.parent / "settings-backups"
    backups.mkdir(mode=0o700, exist_ok=True)
    backup = backups / f"settings-{time.time_ns()}.toml"
    with backup.open("xb") as stream:
        os.chmod(backup, 0o600)
        stream.write(before)
    # Preserve a settings symlink, matching Noctalia's own write-through behavior.
    target = path.resolve()
    with tempfile.NamedTemporaryFile(dir=target.parent, prefix=".settings-", delete=False) as stream:
        stream.write(tomlkit.dumps(settings).encode())
        temporary = Path(stream.name)
    if path.read_bytes() != before:
        raise RuntimeError("Noctalia settings changed during reconciliation; backup retained")
    os.replace(temporary, target)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("executable")
    parser.add_argument("baselines", type=Path)
    parser.add_argument("profile", choices=("hyprland", "mangowm"))
    parser.add_argument("arguments", nargs=argparse.REMAINDER)
    options = parser.parse_args()
    defaults = tomlkit.parse((options.baselines / f"{options.profile}.toml").read_text())
    config_home = os.environ.get("XDG_CONFIG_HOME")
    config = Path(config_home) if config_home else Path.home() / ".config"
    state_home = os.environ.get("XDG_STATE_HOME")
    state = Path(state_home) if state_home else Path.home() / ".local/state"
    os.environ["NOCTALIA_CONFIG_HOME"] = str(config / "noctalia/profiles" / options.profile)
    os.environ["NOCTALIA_STATE_HOME"] = str(state)
    profile = state / "noctalia/profiles" / options.profile
    os.environ["NOCTALIA_PROFILE_STATE_HOME"] = str(profile)
    migrate_history(state)
    reconcile(profile / "noctalia/settings.toml", defaults)
    os.execv(options.executable, [options.executable, *options.arguments])


if __name__ == "__main__":
    main()
