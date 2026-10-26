import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tomllib

import tomlkit
from coloraide import Color


contract = json.loads(Path(sys.argv[1]).read_text())
root = Path(sys.argv[2])
home = contract["home"]
manifest = {entry["destination"]: entry["source"] for entry in contract["manifest"]}
theme = Path(contract["boot"]["theme"])
assert contract["boot"]["splashImage"] == str(theme / "background.jpg")
assert 'desktop-image: "background.jpg"' in (theme / "theme.txt").read_text()
assert (theme / "icons/nixos.png").is_file()
assert contract["gtkTheme"] == "Skadi"
gtk_modules = contract["gtk3Modules"].split(":")
assert any(Path(module).name == "libskadi-palette-reload.so" and Path(module).is_file()
           for module in gtk_modules), gtk_modules
gtk4 = contract["gtk4"]
assert gtk4["configured"] == gtk4["stock"], "GTK4 must not invalidate upstream application builds"
assert len(gtk4["reloadModules"]) == 1, gtk4["reloadModules"]
assert Path(gtk4["reloadModules"][0]).is_file(), "GTK4 palette reload module is not in the user profile"
assert contract["qtStyle"] == "kvantum"
assert contract["qtTheme"] == "Skadi"
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

expected = {"claude-code", "zen-browser", "starship", "equibop", "codex", "obs",
            "gtk-gtk3", "gtk-gtk4", "qt"}
equibop_inputs = set()
for renderer, path in contract["registrations"].items():
    data = tomllib.loads(Path(path).read_text())
    assert expected <= data["templates"].keys(), renderer
    assert not {"qt-qt5ct", "qt-qt6ct"} & data["templates"].keys(), renderer
    for name, relative in [("gtk-gtk3", "gtk-3.0/reactive.css"),
                           ("gtk-gtk4", "gtk-4.0/reactive.css"),
                           ("qt", "qt-theme/palette.json")]:
        destination = f"{home}/.config/{relative}"
        assert data["templates"][name]["output_path"] == destination, renderer
        assert destination not in manifest, (renderer, destination)
    equibop_template = data["templates"]["equibop"]
    assert equibop_template["output_path"] == f"{home}/.config/equibop/themes/reactive.theme.css"
    assert equibop_template["output_path"] not in manifest
    equibop_inputs.add(Path(manifest[equibop_template["input_path"]]))
    assert data["templates"]["zen-browser"]["output_path"] == f"{home}/.config/zen/theme/palette.css", renderer
    for sub_id, name in [("content", "userContent.css"), ("chrome", "userChrome.css")]:
        assert data["templates"][f"zen-browser-{sub_id}"]["output_path"] == f"{home}/.config/zen/theme/{name}", renderer
        assert f"{home}/.config/zen/theme/{name}" not in manifest, renderer
for app in ["zen-browser", "claude-code", "starship", "equibop", "codex", "obs"]:
    path = manifest[f"{home}/.config/noctalia/{app}.toml"]
    data = tomllib.loads(Path(path).read_text())
    assert data["theme"]["templates"]["user"], app
    assert f"{home}/.config/caelestia/theme-hooks/{app}" in manifest
    if app == "equibop":
        template = data["theme"]["templates"]["user"]["equibop"]["input_path"]
        equibop_inputs.add(Path(manifest[template.replace("~/", f"{home}/", 1)]))

equibop_caelestia = Path(manifest[f"{home}/.config/caelestia/templates/equibop-caelestia.css"])

outputs = Path.cwd() / "rendered"
outputs.mkdir()
sources = []
for app in ["zen-browser", "claude-code", "starship", "codex", "obs"]:
    sources.extend(sorted((root / "configs" / app).glob("reactive*")))
sources.extend(sorted(equibop_inputs))
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


def check_equibop_theme(content):
    css = re.sub(r"/\*.*?\*/", "", content, flags=re.S)
    assert not re.search(r"@import\b|url\(\s*['\"]?https?://", css)
    assert '@name System24 Reactive' in content
    assert content.count('font-family: "DM Mono"') == 6
    assert "data:font/woff;base64," in css and "data:image/gif;base64," in css
    assert "data:image/svg+xml;base64," in css
    assert content.count("Copyright (c) 2025 refact0r") == 2
    assert "Copyright 2020 The DM Mono Project Authors" in content
    assert "SIL OPEN FONT LICENSE" in content
    assert "--unrounding: on;" in css and "--panel-labels: on;" in css
    definitions = dict(re.findall(r"(?m)^\s*(--[\w-]+):\s*([^;\n]+);", css))
    compatibility = {
        "--button-outline-brand-background-hover", "--button-outline-brand-border-active",
        "--card-primary-pressed-bg", "--control-brand-foreground-new", "--input-border-readonly",
        "--scrollbar-auto-scrollbar-color-thumb", "--scrollbar-auto-scrollbar-color-track",
        "--spoiler-hidden-background", "--spoiler-hidden-background-hover", "--status-positive-text",
        "--status-warning-background", "--status-warning-text", "--text-overlay-dark",
        "--user-profile-activity-toolbar-background",
    }
    assert compatibility <= definitions.keys()
    for token in compatibility:
        assert definitions[token] not in {"red", "lime", "blue", "yellow", "magenta", "cyan"}, token

    def color(value):
        if value.startswith("var("):
            return color(definitions[value[4:-1]])
        mix = re.fullmatch(r"color-mix\(in ([\w-]+), (.+)\)", value)
        if mix:
            left, right = color_parts(mix[2])
            first = re.fullmatch(r"(.+) (\d+)%", left)
            second = re.fullmatch(r"(.+) (\d+)%", right)
            assert first or second, value
            weight = int(second[2]) / 100 if second else 1 - int(first[2]) / 100
            return color(first[1] if first else left).mix(
                color(second[1] if second else right), weight, space=mix[1], premultiplied=True)
        return Color(value)

    pairs = [(f"--bg-{background}", f"--text-{foreground}")
             for background in range(1, 5) for foreground in range(1, 6)]
    pairs += [(f"--accent-{index}", "--text-0") for index in range(2, 6)]
    pairs += [(f"--{hue}-2", "--text-0") for hue in ["purple", "yellow", "green", "blue", "red"]]
    pairs += [("--bg-4", "--accent-1"),
              ("--status-positive-background", "--status-positive-text"),
              ("--status-warning-background", "--status-warning-text"),
              ("--background-brand", "--text-overlay-dark"),
              ("--custom-notice-background", "--custom-notice-text"),
              ("--custom-notice-button-hover", "--custom-notice-text"),
              ("--button-outline-brand-background-hover", "--control-secondary-text-hover")]
    for kind in ["critical-secondary", "critical-primary", "connected", "primary"]:
        pairs += [(f"--control-{kind}-background-{state}", f"--control-{kind}-text-{state}")
                  for state in ["default", "hover", "active"]]
    failures = []
    for background, foreground in pairs:
        ratio = color(definitions[background]).contrast(color(definitions[foreground]), method="wcag21")
        if ratio < 4.5:
            failures.append((background, foreground, ratio))
    for kind in ["critical", "positive", "warning", "info"]:
        foreground = color(definitions[f"--text-feedback-{kind}"])
        for frame in range(1, 5):
            base = color(definitions[f"--bg-{frame}"])
            ratio = foreground.contrast(base, method="wcag21")
            if ratio < 4.5:
                failures.append((kind, frame, ratio))
            background = Color.layer([color(definitions[f"--background-feedback-{kind}"]), base], space="srgb")
            ratio = foreground.contrast(background, method="wcag21")
            if ratio < 4.5:
                failures.append((kind, frame, "feedback card", ratio))
    assert not failures, failures
    for token in ["--spoiler-hidden-background", "--spoiler-hidden-background-hover"]:
        assert color(definitions[token]).alpha() == 1, token


zen_palettes = []
equibop_palettes = []
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
        if "@name System24 Reactive" in content:
            check_equibop_theme(content)
            equibop_palettes.append(content)

for app in ["zen-browser", "claude-code", "starship", "equibop", "codex", "obs"]:
    for source in (root / "configs" / app).glob("caelestia*"):
        if app == "equibop":
            for palette in equibop_palettes:
                colors = {}
                for role, value in re.findall(r"--skadi-eq-([\w-]+):\s*#([0-9a-fA-F]{6});", palette):
                    parts = role.split("-")
                    colors[parts[0] + "".join(part.title() for part in parts[1:])] = value
                content = re.sub(r"\{\{\s*([A-Za-z0-9]+)\.hex\s*\}\}",
                                 lambda match: colors[match[1]], equibop_caelestia.read_text())
                assert "{{" not in content, source
                check_equibop_theme(content)
            continue
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
