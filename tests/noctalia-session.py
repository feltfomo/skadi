import importlib.util
from pathlib import Path
import sys
import tempfile

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
print("Noctalia settings migration passed")
