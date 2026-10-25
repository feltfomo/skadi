import json
from pathlib import Path
import re
import sys
import tomllib
from urllib.parse import unquote, urlsplit


contract = json.loads(Path(sys.argv[1]).read_text())
skin = Path(sys.argv[2])
home = contract["home"]
theme_directory = contract["themeDirectory"]
manifest = {entry["destination"]: entry for entry in contract["manifest"]}

assert not any("millennium" in path for path in contract["lumiManifest"])
assert not any("Material-Theme" in path for path in manifest)
assert f"{home}/.config/noctalia/steam.toml" not in manifest
assert f"{home}/.config/caelestia/theme-hooks/steam" not in manifest
assert not any("/templates/steam/" in path for path in manifest)
settings_path = f"{home}/.config/millennium/config.json"
assert manifest[settings_path]["representation"] == "writable"
assert manifest[settings_path]["onConflict"] == "source-wins"
settings = json.loads(Path(contract["settings"]).read_text())
theme = settings["themes"]["activeTheme"]
assert theme == "Aika"
skin_config = json.loads((skin / "skin.json").read_text())
assert skin_config["name"] == theme
conditions = skin_config["Conditions"]
for name, value in settings["themes"]["conditions"][theme].items():
    assert value in conditions[name]["values"], (name, value)
    assert value == conditions[name]["default"], (name, value)
assert settings["themes"]["conditions"][theme]["Color preset"] == "Aika"
assert settings["themes"]["conditions"][theme]["Custom colors"] == "no"
assert settings["general"]["injectCSS"] and settings["themes"]["allowedStyles"]
assert settings["general"]["injectJavascript"] and settings["themes"]["allowedScripts"]
assert not settings["general"]["checkForPluginAndThemeUpdates"]

for renderer, path in contract["registrations"].items():
    registration = tomllib.loads(Path(path).read_text())
    assert "steam" not in registration.get("templates", {}), renderer

assets = {}
for destination, entry in manifest.items():
    if destination.startswith(theme_directory + "/"):
        relative = destination.removeprefix(theme_directory + "/")
        original = skin / relative
        assert original.is_file(), relative
        assert Path(entry["source"]).read_bytes() == original.read_bytes(), relative
        assets[relative] = original
assert "skin.json" in assets
assert skin_config["RootColors"] in assets
assert skin_config["Steam-WebKit"] in assets
for patch in skin_config["Patches"]:
    for key in ("TargetCss", "TargetJs"):
        if key in patch:
            assert patch[key] in assets, patch[key]
for condition in conditions.values():
    for value in condition.get("values", {}).values():
        for key in ("TargetCss", "TargetJs"):
            if key in value:
                assert value[key]["src"] in assets, value[key]["src"]
for relative, path in assets.items():
    if path.suffix != ".css":
        continue
    for match in re.finditer(r'''url\(\s*(?:"([^"]*)"|'([^']*)'|([^'"\s)]+))\s*\)''', path.read_text()):
        url = urlsplit(match[1] or match[2] or match[3])
        if url.scheme or url.netloc or not url.path:
            continue
        target = (path.parent / unquote(url.path)).resolve().relative_to(skin.resolve())
        assert str(target) in assets, (relative, str(target))
print("Aika defaults, theme assets, script permissions, and removal of Steam palette registrations passed")
