import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tomllib

import tomlkit


contract = json.loads(Path(sys.argv[1]).read_text())
root = Path(sys.argv[2])
home = contract["home"]
manifest = {entry["destination"]: entry["source"] for entry in contract["manifest"]}
theme = Path(contract["boot"]["theme"])
assert contract["boot"]["splashImage"] == str(theme / "background.jpg")
assert 'desktop-image: "background.jpg"' in (theme / "theme.txt").read_text()
assert (theme / "icons/nixos.png").is_file()
assert contract["gtkTheme"] == "Colloid-Grey-Dark-Compact"
assert contract["starship"]
assert not any("obs-studio/themes/Reactive" in path for path in contract["lumiManifest"])

descriptors = [json.loads(Path(source).read_text()) for destination, source in manifest.items()
               if destination.startswith(f"{home}/.config/lexicon/toml/")]
starship = next(value for value in descriptors if value["output"] == f"{home}/.config/starship.toml")
base = tomllib.loads(Path(starship["base"]).read_text())
prompt_config = Path.cwd() / "starship.toml"
prompt_config.write_text(tomlkit.dumps(base))
project = Path.cwd() / "project"
project.mkdir()
(project / "package.json").write_text('{"name":"project","version":"1.2.3"}')
subprocess.run(["git", "init", "--initial-branch=main", str(project)], check=True, capture_output=True)
environment = dict(os.environ, STARSHIP_CONFIG=str(prompt_config),
                   STARSHIP_CACHE=str(Path.cwd() / "starship-cache"), PWD=str(project))
prompt = subprocess.run(["starship", "prompt", "--path", str(project)],
                        check=True, capture_output=True, text=True, env=environment, cwd=project)
assert "project" in prompt.stdout and "1.2.3" in prompt.stdout and "main" in prompt.stdout, (prompt.stdout, prompt.stderr)
assert "?" in prompt.stdout and not prompt.stderr, prompt.stderr

expected = {"zen-browser-content", "zen-browser-chrome", "claude-code", "starship", "equibop", "codex", "obs"}
for renderer, path in contract["registrations"].items():
    data = tomllib.loads(Path(path).read_text())
    assert expected <= data["templates"].keys(), renderer
for app in ["zen-browser", "claude-code", "starship", "equibop", "codex", "obs"]:
    path = manifest[f"{home}/.config/noctalia/{app}.toml"]
    data = tomllib.loads(Path(path).read_text())
    assert data["theme"]["templates"]["user"], app
    assert f"{home}/.config/caelestia/theme-hooks/{app}" in manifest

outputs = Path.cwd() / "rendered"
outputs.mkdir()
sources = []
for app in ["zen-browser", "claude-code", "starship", "equibop", "codex", "obs"]:
    sources.extend(sorted((root / "configs" / app).glob("reactive*")))
config = ["[config]", "reload_apps = false", ""]
for index, source in enumerate(sources):
    output = outputs / f"{index}{source.suffix}"
    config.extend([
        f"[templates.app{index}]",
        f"input_path = {json.dumps(str(source))}",
        f"output_path = {json.dumps(str(output))}",
        "",
    ])
path = Path.cwd() / "matugen.toml"
path.write_text("\n".join(config))
for mode in ["dark", "light"]:
    subprocess.run(["matugen", "color", "hex", "#89b4fa", "--mode", mode, "--config", str(path)], check=True)
    for output in outputs.iterdir():
        content = output.read_text()
        assert "{{" not in content, output
        if output.suffix == ".json":
            data = json.loads(content)
            assert data["name"] == "Reactive"
        elif output.suffix == ".toml":
            tomllib.loads(content)
        elif output.suffix == ".tmTheme":
            plistlib.loads(content.encode())
        else:
            assert content.count("{") == content.count("}"), output

for app in ["zen-browser", "claude-code", "starship", "equibop", "codex", "obs"]:
    for source in (root / "configs" / app).glob("caelestia*"):
        content = re.sub(r"\{\{\s*[A-Za-z0-9]+\.hex\s*\}\}", "89b4fa", source.read_text())
        assert "{{" not in content, source
        if source.suffix == ".json":
            json.loads(content)
        elif source.suffix == ".toml":
            tomllib.loads(content)
        elif source.suffix == ".tmTheme":
            plistlib.loads(content.encode())

print("GRUB artwork, host ownership, renderer registrations, and dark/light Matugen renders passed")
