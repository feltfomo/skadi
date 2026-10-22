import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

import tomlkit

cli, fixtures = sys.argv[1:]
for fixture in json.loads(Path(fixtures).read_text()):
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        assert Path(fixture["descriptor"]).read_bytes() == Path(fixture["retained"][0]).read_bytes()
        spec = json.loads(Path(fixture["descriptor"]).read_text())
        base = tomlkit.parse(Path(spec["base"]).read_text())
        assert base["onboarding"] is False
        assert [binding["key"] for binding in base["keys"]["command"]] == ["prefix+f", "prefix+e", "prefix+o"]
        assert base["ui"]["toast"]["delivery"] == "herdr"
        assert base["theme"]["name"] == "kanagawa-lotus"
        spec["output"] = str(root / "config.toml")
        spec["state"] = str(root / "state")
        descriptor = root / "current.json"
        descriptor.write_text(json.dumps(spec))
        environment = os.environ.copy()
        # An absent private socket exercises the real closure's cold-boot path.
        environment["HERDR_SOCKET_PATH"] = str(root / "absent.sock")
        def publish(*args):
            subprocess.run([cli, "publish", str(descriptor), *args], env=environment, check=True, timeout=30)
            return tomlkit.parse(Path(spec["output"]).read_text())
        assert publish()["onboarding"] is False
        for index, source in enumerate(fixture["palettes"]):
            text = re.sub(r"#?\{\{.*?\}\}", f"#{index+1:06x}", Path(source).read_text())
            palette = tomlkit.parse(text)
            assert set(palette) == {"ui", "theme"}
            assert set(palette["ui"]) == {"accent"}
            assert set(palette["theme"]) == {"custom"}
            staging = root / "staging.toml"
            staging.write_text(text)
            current = publish("--theme", str(staging))
            assert current["onboarding"] is False
            assert len(current["keys"]["command"]) == 3
            before = Path(spec["output"]).stat().st_mtime_ns
            publish()
            assert Path(spec["output"]).stat().st_mtime_ns == before
        updated = root / "new-base.toml"
        base["keys"]["command"][0]["description"] = "updated without wallpaper"
        updated.write_text(tomlkit.dumps(base))
        spec["base"] = str(updated)
        descriptor.write_text(json.dumps(spec))
        assert publish()["keys"]["command"][0]["description"] == "updated without wallpaper"
        assert publish("--theme", str(staging))["keys"]["command"][0]["description"] == "updated without wallpaper"
print("Both hosts publish Herdr base changes without a wallpaper event and retain bindings across palettes")
