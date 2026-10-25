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

expected = {"claude-code", "zen-browser", "starship", "equibop", "codex", "obs"}
for renderer, path in contract["registrations"].items():
    data = tomllib.loads(Path(path).read_text())
    assert expected <= data["templates"].keys(), renderer
    assert data["templates"]["zen-browser"]["output_path"] == f"{home}/.config/zen/theme/palette.css", renderer
    for sub_id, name in [("content", "userContent.css"), ("chrome", "userChrome.css")]:
        assert data["templates"][f"zen-browser-{sub_id}"]["output_path"] == f"{home}/.config/zen/theme/{name}", renderer
        assert f"{home}/.config/zen/theme/{name}" not in manifest, renderer
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
zen_entries = [root / "configs/zen-browser/theme" / name
               for name in ["userContent.css", "userChrome.css"]]
sources.extend(zen_entries)
config = ["[config]", "reload_apps = false", ""]
for index, source in enumerate(sources):
    output = outputs / f"{index}{source.suffix}"
    if source in zen_entries:
        output.write_text(".legacy-theme { color: gray; }\n")
    config.extend([
        f"[templates.app{index}]",
        f"input_path = {json.dumps(str(source))}",
        f"output_path = {json.dumps(str(output))}",
        "",
    ])
path = Path.cwd() / "matugen.toml"
path.write_text("\n".join(config))


zen_root = root / "configs/zen-browser/theme"
zen_files = {path.name: path.read_text() for path in zen_root.glob("*.css")}
for name, content in zen_files.items():
    if name in {entry.name for entry in zen_entries}:
        continue
    furnished = Path(manifest[f"{home}/.config/zen/theme/{name}"])
    assert furnished.read_text() == content, name


def imported_files(name, visiting=()):
    assert name not in visiting, f"CSS import cycle: {visiting + (name,)}"
    if name == "palette.css":
        return {name}
    assert name in zen_files, f"Missing furnished stylesheet {name}"
    result = {name}
    for imported in re.findall(r'@import url\("([^"\n]+)"\);', zen_files[name]):
        result |= imported_files(imported, visiting + (name,))
    return result


chrome_files = imported_files("userChrome.css")
content_files = imported_files("userContent.css")
assert chrome_files | content_files == set(zen_files) | {"palette.css"}
assert chrome_files & content_files == {"palette.css", "materials.css"}
assert '@-moz-document url("about:newtab")' in zen_files["content.css"]
assert 'url-prefix("about:")' not in zen_files["content.css"]


def color_parts(value):
    depth = 0
    start = 0
    result = []
    for index, char in enumerate(value):
        depth += (char == "(") - (char == ")")
        if char == "," and depth == 0:
            result.append(value[start:index].strip())
            start = index + 1
    return result + [value[start:].strip()]


def check_zen_palette(content, state=""):
    definitions = dict(re.findall(r"(--skadi-[\w-]+):\s*([^;]+);", content + zen_files["materials.css"] + state))
    referenced = set(re.findall(r"var\((--skadi-[\w-]+)\)", "\n".join(zen_files.values())))
    assert referenced <= definitions.keys(), referenced - definitions.keys()

    def color(value):
        if value.startswith("var("):
            return color(definitions[value[4:-1]])
        if re.fullmatch(r"#[0-9a-fA-F]{6}", value):
            return tuple(int(value[index:index + 2], 16) / 255 for index in [1, 3, 5]) + (1,)
        if value == "transparent":
            return (0, 0, 0, 0)
        assert value.startswith("color-mix(in srgb, "), value
        left, right = color_parts(value[len("color-mix(in srgb, "):-1])
        match = re.fullmatch(r"(.+) (\d+)%", left)
        assert match, left
        weight = int(match[2]) / 100
        first, second = color(match[1]), color(right)
        alpha = first[3] * weight + second[3] * (1 - weight)
        return tuple((a * first[3] * weight + b * second[3] * (1 - weight)) / alpha
                     for a, b in zip(first[:3], second[:3])) + (alpha,)

    def luminance(rgba, backdrop):
        rgb = [component * rgba[3] + backdrop * (1 - rgba[3]) for component in rgba[:3]]
        linear = [value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4 for value in rgb]
        return sum(value * weight for value, weight in zip(linear, [0.2126, 0.7152, 0.0722]))

    for background in ["shell", "panel", "shell-material", "panel-material", "field", "hover", "selected"]:
        foregrounds = ["selected-text"] if background == "selected" else ["text", "muted"]
        for foreground in foregrounds:
            for backdrop in [0, 1]:
                pair = [luminance(color(definitions[f"--skadi-{role}"]), backdrop)
                        for role in [background, foreground]]
                ratio = (max(pair) + 0.05) / (min(pair) + 0.05)
                assert ratio >= 4.5, (background, foreground, backdrop, ratio)


def check_zen_states(content):
    check_zen_palette(content)
    for selector in [':root[zen-private-window="true"]',
                     ':root[zen-unsynced-window="true"]:not([zen-private-window="true"])',
                     ':root:-moz-window-inactive']:
        match = re.search(re.escape(selector) + r"\s*\{([^}]+)\}", zen_files["chrome.css"])
        assert match, selector
        check_zen_palette(content, match[1])


zen_palettes = []
for mode in ["dark", "light"]:
    subprocess.run(["matugen", "color", "hex", "#89b4fa", "--mode", mode, "--config", str(path)], check=True)
    for entry in zen_entries:
        output = outputs / f"{sources.index(entry)}{entry.suffix}"
        assert output.read_text() == entry.read_text(), entry
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
        if "--skadi-primary:" in content:
            check_zen_states(content)
            zen_palettes.append(content)

for app in ["zen-browser", "claude-code", "starship", "equibop", "codex", "obs"]:
    for source in (root / "configs" / app).glob("caelestia*"):
        if app == "zen-browser":
            for palette in zen_palettes:
                colors = {}
                for role, value in re.findall(r"--skadi-([\w-]+):\s*#([0-9a-fA-F]{6});", palette):
                    parts = role.split("-")
                    colors[parts[0] + "".join(part.title() for part in parts[1:])] = value
                content = re.sub(r"\{\{\s*([A-Za-z0-9]+)\.hex\s*\}\}",
                                 lambda match: colors[match[1]], source.read_text())
                assert "{{" not in content, source
                check_zen_states(content)
            continue
        content = re.sub(r"\{\{\s*[A-Za-z0-9]+\.hex\s*\}\}", "89b4fa", source.read_text())
        assert "{{" not in content, source
        if source.suffix == ".json":
            json.loads(content)
        elif source.suffix == ".toml":
            tomllib.loads(content)
        elif source.suffix == ".tmTheme":
            plistlib.loads(content.encode())

print("GRUB artwork, host ownership, renderer registrations, CSS imports, contrast, and dark/light renders passed")
