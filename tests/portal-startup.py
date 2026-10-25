import configparser
import os
from pathlib import Path
import subprocess
import sys
import tempfile


unit = configparser.ConfigParser(interpolation=None)
unit.read_string(Path(sys.argv[1]).read_text())
condition = unit["Unit"]["ConditionEnvironment"]
assert condition == "WAYLAND_DISPLAY"
assert "graphical-session.target" not in unit["Unit"].get("Requisite", "")

with tempfile.TemporaryDirectory() as runtime:
    environment = dict(os.environ)
    environment["XDG_RUNTIME_DIR"] = runtime
    environment.pop("WAYLAND_DISPLAY", None)
    command = ["systemd-analyze", "--user", "condition", f"ConditionEnvironment={condition}"]
    before_login = subprocess.run(command, env=environment, capture_output=True, text=True)
    assert before_login.returncode == 1, before_login.stderr
    environment["WAYLAND_DISPLAY"] = "wayland-test"
    after_login = subprocess.run(command, env=environment, capture_output=True, text=True)
    assert after_login.returncode == 0, after_login.stderr
print("Portal activation waits for the compositor display without requiring a managed session target")
