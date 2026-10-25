import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
from unittest.mock import patch

import tomlkit

spec = importlib.util.spec_from_file_location("session", sys.argv[1])
session = importlib.util.module_from_spec(spec)
spec.loader.exec_module(session)

defaults = {
    "plugins": {"enabled": ["miguelfm/ai-triage"]},
    "bar": {"default": {"start": ["workspaces", "bar"]}},
    "shell": {"font_family": "Maple Mono NF"},
}
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    path = root / "settings.toml"
    session.reconcile(path, defaults)
    assert not path.exists()
    before = '''config_version = 15
[shell]
font_family = "Maple Mono NF"
telemetry_enabled = false
[plugins]
enabled = ["miguelfm/ai-triage"]
[bar.default]
start = ["workspaces", "indicator", "bar"]
[widget.indicator]
type = "fel/agent-glow:indicator"
[widget.bar]
type = "miguelfm/ai-triage:bar"
[plugin_settings."fel/agent-glow"]
saved_option = true
'''
    path.write_text(before)
    session.reconcile(path, defaults)
    settings = tomlkit.parse(path.read_text())
    assert settings["shell"] == {"telemetry_enabled": False}
    assert "bar" not in settings and "plugins" not in settings
    assert "indicator" not in settings["widget"]
    assert settings["widget"]["bar"]["type"] == "miguelfm/ai-triage:bar"
    assert settings["plugin_settings"]["fel/agent-glow"]["saved_option"]
    backups = list((root / "settings-backups").iterdir())
    assert len(backups) == 1 and backups[0].read_text() == before
    assert backups[0].stat().st_mode & 0o777 == 0o600
    session.reconcile(path, defaults)
    assert len(list((root / "settings-backups").iterdir())) == 1
    path.write_text('[shell]\nfont_family = "Different font"\n')
    session.reconcile(path, defaults)
    assert tomlkit.parse(path.read_text())["shell"]["font_family"] == "Different font"
    target = root / "writable.toml"
    path.rename(target)
    path.symlink_to(target)
    target.write_text(before)
    session.reconcile(path, defaults)
    assert path.is_symlink() and "bar" not in tomlkit.parse(target.read_text())
    target.write_text("invalid = [")
    try:
        session.reconcile(path, defaults)
    except tomlkit.exceptions.ParseError:
        pass
    else:
        raise AssertionError("invalid TOML must fail without rewriting settings")
    assert target.read_text() == "invalid = ["
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    baselines = root / "baselines"
    baselines.mkdir()
    state = root / "state"
    legacy = state / "noctalia/settings.toml"
    legacy.parent.mkdir(parents=True)
    legacy.write_text('[shell]\nfont_family = "Legacy"\n')
    paths = {}
    for profile, font in (("hyprland", "Hyprland font"), ("mangowm", "Mango font")):
        (baselines / f"{profile}.toml").write_text(tomlkit.dumps({
            "plugins": {"enabled": []},
            "shell": {"font_family": font},
        }))
        paths[profile] = state / "noctalia/profiles" / profile / "noctalia/settings.toml"
        paths[profile].parent.mkdir(parents=True)
        paths[profile].write_text(tomlkit.dumps({"shell": {"font_family": font}}))
    mango_before = paths["mangowm"].read_bytes()
    environment = {
        "XDG_CONFIG_HOME": str(root / "config"),
        "XDG_STATE_HOME": str(state),
        "NOCTALIA_CONFIG_HOME": "/stale/config",
        "NOCTALIA_PROFILE_STATE_HOME": "/stale/profile",
        "NOCTALIA_STATE_HOME": "/stale/state",
    }
    for index, profile in enumerate(("hyprland", "mangowm", "hyprland")):
        argv = ["session", "/fake/noctalia", str(baselines), profile, "--debug"]
        with (
            patch.dict(os.environ, environment, clear=True),
            patch.object(sys, "argv", argv),
            patch.object(session.os, "execv") as execute,
        ):
            session.main()
            execute.assert_called_once_with("/fake/noctalia", ["/fake/noctalia", "--debug"])
            assert os.environ["NOCTALIA_CONFIG_HOME"] == str(root / "config/noctalia/profiles" / profile)
            assert os.environ["NOCTALIA_PROFILE_STATE_HOME"] == str(state / "noctalia/profiles" / profile)
            assert os.environ["NOCTALIA_STATE_HOME"] == str(state)
            assert os.environ["XDG_CONFIG_HOME"] == environment["XDG_CONFIG_HOME"]
            assert os.environ["XDG_STATE_HOME"] == environment["XDG_STATE_HOME"]
        assert not tomlkit.parse(paths[profile].read_text())
        assert legacy.read_text() == '[shell]\nfont_family = "Legacy"\n'
        if index == 0:
            assert paths["mangowm"].read_bytes() == mango_before
    for path in paths.values():
        assert len(list((path.parent / "settings-backups").iterdir())) == 1

with tempfile.TemporaryDirectory() as directory:
    state = Path(directory)
    shared = state / "noctalia"
    profile = shared / "profiles/hyprland/noctalia"
    mango = shared / "profiles/mangowm/noctalia"
    for path in (profile, mango, shared):
        path.mkdir(parents=True, exist_ok=True)
    histories = {
        profile: ({"apps": {"shared": 3, "new": 1}}, {"apps": ["new", "shared"]}),
        shared: ({"apps": {"shared": 8, "old": 2}}, {"apps": ["shared", "old"]}),
        mango: ({"apps": {"mango": 1}}, {"apps": ["mango"]}),
    }
    for timestamp, (path, (counts, recent)) in enumerate(histories.items(), start=1):
        (path / "usage_counts.json").write_text(json.dumps(counts))
        (path / "recently_used.json").write_text(json.dumps(recent))
        os.utime(path / "recently_used.json", ns=(timestamp, timestamp))
    clipboard_contents = {
        profile: (b"new encrypted index", b"new encrypted payload"),
        shared: (b"old encrypted index", b"old encrypted payload"),
    }
    for timestamp, (path, (manifest, payload)) in enumerate(clipboard_contents.items(), start=1):
        entries = path / "clipboard/entries"
        entries.mkdir(parents=True)
        (path / "clipboard/index.enc").write_bytes(manifest)
        (entries / "payload.enc").write_bytes(payload)
        os.utime(path / "clipboard/index.enc", ns=(timestamp, timestamp))
    os.utime(profile / "clipboard/index.enc", ns=(10, 10))
    session.migrate_history(state)
    assert json.loads((shared / "usage_counts.json").read_text()) == {
        "apps": {"shared": 8, "new": 1, "old": 2, "mango": 1}
    }
    assert json.loads((shared / "recently_used.json").read_text()) == {
        "apps": ["mango", "shared", "old", "new"]
    }
    assert (shared / "clipboard/index.enc").read_bytes() == b"new encrypted index"
    assert (shared / "clipboard/entries/payload.enc").read_bytes() == b"new encrypted payload"
    assert (profile / "clipboard/index.enc").read_bytes() == b"new encrypted index"
    archives = list((shared / "history-backups").iterdir())
    assert len(archives) == 1
    assert (archives[0] / "clipboard/index.enc").read_bytes() == b"old encrypted index"
    assert json.loads((archives[0] / "shared/usage_counts.json").read_text()) == histories[shared][0]
    (shared / "usage_counts.json").write_text("{}")
    session.migrate_history(state)
    assert (shared / "usage_counts.json").read_text() == "{}"
    assert len(list((shared / "history-backups").iterdir())) == 1

with tempfile.TemporaryDirectory() as directory:
    state = Path(directory)
    shared = state / "noctalia"
    profile = shared / "profiles/hyprland/noctalia"
    profile.mkdir(parents=True)
    (shared / "usage_counts.json").write_text("invalid = [")
    (profile / "usage_counts.json").write_text('{"apps": {"valid": 1}}')
    recent = [f"app-{index}" for index in range(25)]
    (profile / "recently_used.json").write_text(json.dumps({"apps": recent}))
    session.migrate_history(state)
    assert json.loads((shared / "usage_counts.json").read_text()) == {"apps": {"valid": 1}}
    assert json.loads((shared / "recently_used.json").read_text()) == {"apps": recent[:20]}
    archive = next((shared / "history-backups").iterdir())
    assert (archive / "shared/usage_counts.json").read_text() == "invalid = ["
print("Noctalia history migration and profile settings isolation passed")
