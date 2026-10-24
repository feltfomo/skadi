import os
from pathlib import Path
import sys
import tempfile
import time

import tomlkit


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
    executable, baseline, *arguments = sys.argv[1:]
    defaults = tomlkit.parse(Path(baseline).read_text())
    state_home = os.environ.get("NOCTALIA_STATE_HOME") or os.environ.get("XDG_STATE_HOME")
    state = Path(state_home) if state_home else Path.home() / ".local/state"
    reconcile(state / "noctalia/settings.toml", defaults)
    os.execv(executable, [executable, *arguments])


if __name__ == "__main__":
    main()
