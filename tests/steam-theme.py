import json
from pathlib import Path
import re
import subprocess
import sys
import tomllib


contract = json.loads(Path(sys.argv[1]).read_text())
skin = Path(sys.argv[2])
caelestia = Path(sys.argv[3])
home = contract["home"]
output = contract["output"]
manifest = {entry["destination"]: entry for entry in contract["manifest"]}

assert output not in manifest, "the renderer must own its writable output"
assert not any("millennium" in path for path in contract["lumiManifest"])
settings_path = f"{home}/.config/millennium/config.json"
assert manifest[settings_path]["representation"] == "writable"
assert manifest[settings_path]["onConflict"] == "source-wins"
settings = json.loads(Path(contract["settings"]).read_text())
theme = settings["themes"]["activeTheme"]
assert theme == "Material-Theme"
conditions = json.loads((skin / "skin.json").read_text())["Conditions"]
for name, value in settings["themes"]["conditions"][theme].items():
    assert value in conditions[name]["values"], (name, value)
assert settings["themes"]["conditions"][theme]["Color"] == "Matugen"
assert settings["general"]["injectJavascript"] and settings["themes"]["allowedScripts"]
assert not settings["general"]["checkForPluginAndThemeUpdates"]

for renderer, path in contract["registrations"].items():
    registration = tomllib.loads(Path(path).read_text())
    if renderer == "noctalia":
        entry = registration["theme"]["templates"]["user"]["steam"]
        actual_output = entry["output_path"].replace("~/", f"{home}/", 1)
    else:
        entry = registration["templates"]["steam"]
        actual_output = entry["output_path"]
    assert actual_output == output, (renderer, actual_output)
    assert "post_hook" not in entry, "palette changes must not restart Steam"
assert output.removeprefix(f"{home}/") in Path(contract["caelestiaHook"]).read_text()

required = set()
for path in skin.rglob("*.css"):
    required.update(re.findall(r"var\((--md-sys-color-[\w-]+)", path.read_text()))


def check_css(text):
    assert "{{" not in text and "<*" not in text
    variables = dict(re.findall(r"(--md-sys-color-[\w-]+)\s*:\s*([^;]+);", text))
    assert required <= variables.keys(), required - variables.keys()
    assert all(re.fullmatch(r"#[\da-fA-F]{6}|rgb\(\d+,\s*\d+,\s*\d+\)", value)
               for value in variables.values())
    return variables


template = Path(contract["caelestiaTemplate"]).read_text()
for palette_path in (caelestia / "src/caelestia/data/schemes").rglob("*.txt"):
    palette = dict(line.split() for line in palette_path.read_text().splitlines() if line)
    rendered = re.sub(r"\{\{ (\w+)\.hex \}\}", lambda match: palette[match[1]], template)
    check_css(rendered)

config = Path("matugen.toml")
rendered_path = Path("matugen.css").resolve()
config.write_text(
    '[config]\n[templates.steam]\n'
    f'input_path = {json.dumps(contract["reactiveTemplate"])}\n'
    f'output_path = {json.dumps(str(rendered_path))}\n'
)
palettes = []
for mode, color in (("dark", "#7851a9"), ("light", "#008080")):
    subprocess.run(["matugen", "--config", str(config), "--mode", mode, "color", "hex", color], check=True)
    palettes.append(check_css(rendered_path.read_text()))
assert palettes[0]["--md-sys-color-primary"] != palettes[1]["--md-sys-color-primary"]
assert palettes[0]["--md-sys-color-surface"] != palettes[1]["--md-sys-color-surface"]
assert not rendered_path.is_symlink()
print("Steam registrations, writable ownership, and reactive palettes passed")
