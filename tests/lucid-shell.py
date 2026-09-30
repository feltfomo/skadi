import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import tomllib


def check_monitors(data):
    source = (data / "shell/Monitors.qml").read_text()
    methods = []
    for name in ("keyFor", "output", "keyForName", "nameOf", "screenFor"):
        match = re.search(r"^    function " + name + r"\(.*?^    \}", source, re.M | re.S)
        assert match, name
        methods.append(name + ": " + match[0].strip())
    probe = re.search(r"            onStreamFinished: \{\n(.*?)^            \}", source, re.M | re.S)
    assert probe
    script = '''
const assert = require("node:assert/strict");
const root = {outputs: [], probed: false};
const Quickshell = {screens: []};
const Hyprland = {
    monitors: {values: []},
    monitorFor: screen => Hyprland.monitors.values.find(m => m.name === screen.name)
};
Object.assign(root, {METHODS});
function probe(monitors) {
    Hyprland.monitors.values = monitors;
    Quickshell.screens = monitors.map(m => ({name: m.name}));
    (function () { PROBE }).call({text: JSON.stringify(monitors)});
}
const duplicates = [
    {name: "DP-1", description: "Identical monitor 123"},
    {name: "DP-2", description: "Identical monitor 123"}
];
Hyprland.monitors.values = duplicates;
assert.equal(root.keyFor("DP-2", duplicates[1].description), "DP-2");
probe(duplicates);
assert.deepEqual(root.outputs.map(m => m.key), ["DP-1", "DP-2"]);
for (const output of root.outputs) {
    assert.equal(root.nameOf(output.key), output.name);
    assert.equal(root.screenFor(output.key).name, output.name);
    assert.equal(root.keyForName(output.name), output.key);
}
probe([
    {name: "DP-3", description: "Unique left"},
    {name: "DP-4", description: "Unique right"}
]);
assert.equal(root.keyForName("DP-4"), "desc:Unique right");
assert.equal(root.screenFor("desc:Unique right").name, "DP-4");
probe([{name: "DP-2", description: ""}]);
assert.equal(root.keyForName("DP-2"), "DP-2");
console.log("lucid-shell: duplicate, unique and unnamed monitor identities passed");
'''.replace("METHODS", ",\n".join(methods)).replace("PROBE", probe[1])
    subprocess.run(["node", "-e", script], check=True)


def check_environment_scopes(data, root, environment):
    home = root / "environment-home"
    home.mkdir()
    log = root / "environment-commands"
    log.write_text("")
    tools = root / "environment-bin"
    tools.mkdir()
    for name in ("gsettings", "hyprctl"):
        tool = tools / name
        tool.write_text(f"#!{shutil.which('sh')}\nprintf '%s\\n' " + json.dumps(name) + ' "$@" >> "$TEST_LOG"\n')
        tool.chmod(0o755)
    env = environment | {"HOME": str(home), "PATH": str(tools) + ":" + environment["PATH"], "TEST_LOG": str(log)}
    cfg = {
        "applyGtk": False, "applyQt": False, "applyHypr": False,
        "cursorTheme": "test-cursor", "cursorSize": 48,
        "iconTheme": "test-icons", "appFont": "test-font", "colorScheme": "dark",
    }
    helper = data / "shell/lucidprefs/envtool.py"
    result = json.loads(subprocess.check_output([sys.executable, str(helper), "apply", json.dumps(cfg)], env=env, text=True))
    assert result["touched"] == [], result
    assert log.read_text() == "", log.read_text()
    assert not (home / ".icons/default/index.theme").exists()
    cfg["applyHypr"] = True
    result = json.loads(subprocess.check_output([sys.executable, str(helper), "apply", json.dumps(cfg)], env=env, text=True))
    assert "hyprctl" in result["touched"], result
    assert log.read_text().splitlines() == ["hyprctl", "setcursor", "test-cursor", "48"]
    assert not (home / ".icons/default/index.theme").exists()
    print("lucid-shell: disabled environment scopes and opt-in cursor application passed")


data = Path(sys.argv[1])
config = tomllib.loads(Path(sys.argv[2]).read_text())
seeds = json.loads(Path(sys.argv[3]).read_text())

expected = {
    "bat", "btop", "cava", "firefox-chrome", "firefox-content", "fuzzel",
    "ghostty", "gtk-gtk3", "gtk-gtk4", "helix", "herdr", "hyprland", "kitty",
    "lucid-shell", "nvim", "qt-qt5ct", "qt-qt6ct", "zed",
}
assert set(config["templates"]) == expected, sorted(config["templates"])
assert len(seeds) == len({seed["dest"] for seed in seeds})
sources = {seed["dest"]: seed["source"] for seed in seeds}

with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    hooks = root / "hooks"
    render_config = root / "render.toml"
    lines = ["[config]"]
    reloads = set()
    for name, template in config["templates"].items():
        relative = template["input_path"].split("/", 3)[3]
        assert relative in sources, relative
        lines += [
            f"[templates.{name}]",
            "input_path = " + json.dumps(sources[relative]),
            "output_path = " + json.dumps(str(root / "outputs" / name)),
        ]
        if "post_hook" in template:
            reloads.add(name)
            lines.append("post_hook = " + json.dumps(f"printf '%s\\n' '{name}' >> '{hooks}'"))
    render_config.write_text("\n".join(lines) + "\n")
    assert "nvim" in reloads
    assert "colorscheme reactive" in config["templates"]["nvim"]["post_hook"]
    palettes = []
    for mode in ("dark", "light"):
        subprocess.run([
            "matugen", "-c", str(render_config), "image",
            str(data / "shell/luciddocks/fallback.jpg"), "-m", mode,
            "--source-color-index", "0",
        ], check=True)
        outputs = {name: (root / "outputs" / name).read_text() for name in expected}
        assert all(text and "{{" not in text for text in outputs.values())
        palettes.append(outputs)
    assert palettes[0]["lucid-shell"] != palettes[1]["lucid-shell"]
    # Neovim stores both schemes in one file; its background selects the
    # active table independently of Matugen's output mode.
    nvim_palette = root / "nvim.lua"
    nvim_palette.write_text(palettes[0]["nvim"])
    select_palette = root / "select-palette.lua"
    select_palette.write_text('''
vim = { o = { background = arg[2] } }
local palette = dofile(arg[1])
assert(#palette.term == 16)
io.write(palette.primary, "\\n")
''')
    for index, mode in enumerate(("dark", "light")):
        primary = subprocess.check_output([
            "lua", str(select_palette), str(nvim_palette), mode,
        ], text=True).strip()
        assert primary == json.loads(palettes[index]["lucid-shell"])["primary"]

    wallpaper_palettes = []
    for color in ("#ff0000", "#0000ff"):
        image = root / (color[1:] + ".png")
        subprocess.run(["magick", "-size", "32x32", "xc:" + color, str(image)], check=True)
        subprocess.run([
            "matugen", "-c", str(render_config), "image", str(image),
            "-m", "dark", "--source-color-index", "0",
        ], check=True)
        wallpaper_palettes.append({name: (root / "outputs" / name).read_text() for name in expected})
    assert wallpaper_palettes[0]["nvim"] != wallpaper_palettes[1]["nvim"]
    assert wallpaper_palettes[0]["lucid-shell"] != wallpaper_palettes[1]["lucid-shell"]
    assert sorted(hooks.read_text().splitlines()) == sorted(list(reloads) * 4)

    home = root / "home"
    helpers = home / ".config/lucid"
    helpers.mkdir(parents=True)
    for source in (data / "helpers").iterdir():
        (helpers / source.name).symlink_to(source)
    cache = home / ".cache"
    cache.mkdir()
    (cache / "current_theme").write_text("matugen")
    (cache / "current_mode").write_text("light")
    wallpaper = root / "wallpaper with spaces.jpg"
    wallpaper.write_bytes((data / "shell/luciddocks/fallback.jpg").read_bytes())
    tools = root / "bin"
    tools.mkdir()
    log = root / "commands"
    for name in ("awww", "matugen", "hyprctl"):
        script = tools / name
        script.write_text(f"#!{shutil.which('sh')}\nprintf '%s\\n' " + json.dumps(name) + ' "$@" >> "$TEST_LOG"\n')
        script.chmod(0o755)
    environment = os.environ | {"HOME": str(home), "PATH": str(tools) + ":" + os.environ["PATH"], "TEST_LOG": str(log)}
    subprocess.run([str(data / "helpers/set-wallpaper.sh"), str(wallpaper)], env=environment, check=True)
    calls = log.read_text().splitlines()
    assert calls.count("matugen") == 1
    index = calls.index("matugen")
    assert calls[index + 1:index + 9] == ["-c", str(helpers / "matugen/config.toml"), "image", str(wallpaper), "-m", "light", "--source-color-index", "0"]
    assert (cache / "current_wallpaper").read_text() == str(wallpaper)

    log.write_text("")
    (cache / "current_theme").write_text("nord")
    subprocess.run([str(data / "helpers/set-wallpaper.sh"), str(wallpaper), "dark"], env=environment, check=True)
    assert "matugen" not in log.read_text().splitlines()
    assert (cache / "current_mode").read_text() == "dark"

    starship = home / ".config/starship.toml"
    starship.write_text("managed prompt\n")
    subprocess.run([str(data / "helpers/apply-theme.sh"), "nord", "dark"], env=environment, check=True)
    assert starship.read_text() == "managed prompt\n"
    assert json.loads((cache / "quickshell/matugen.json").read_text())["primary"]

    dock = (data / "shell/luciddocks/Dock.qml").read_text()
    assert "$HOME/.nix-profile/share/applications" in dock
    assert "/etc/profiles/per-user/$USER/share/applications" in dock
    assert '/.config/quickshell/lucid/' in (data / "shell/Theme.qml").read_text()
    assert "/run/opengl-driver/share/vulkan/icd.d" in (data / "helpers/launch-shell.sh").read_text()
    driver = root / "nvidia-version"
    device = root / "drm/card0/device"
    device.mkdir(parents=True)
    (device / "vendor").write_text("0x10de\n")
    icd_dir = root / "icd"
    icd_dir.mkdir()
    library = root / "libnvidia.so"
    library.touch()
    (icd_dir / "nvidia_icd.json").write_text(json.dumps({"ICD": {"library_path": str(library)}}))
    gpu_env = environment | {
        "LUCID_NVIDIA_VERSION_FILE": str(driver),
        "LUCID_DRM_DIR": str(root / "drm"),
        "LUCID_VULKAN_ICD_DIR": str(icd_dir),
    }
    for key in ("QSG_RHI_BACKEND", "LUCID_RHI_BACKEND", "AQ_DRM_DEVICES", "WLR_DRM_DEVICES"):
        gpu_env.pop(key, None)
    for flavor in ("Kernel Module", "Open Kernel Module for x86_64"):
        driver.write_text(f"NVRM version: NVIDIA UNIX {flavor}  615.71.09  Release Build\n")
        result = subprocess.check_output([str(data / "helpers/launch-shell.sh"), "--explain"], env=gpu_env, text=True)
        assert "backend: vulkan" in result, result
    (device / "vendor").write_text("0x1002\n")
    result = subprocess.check_output([str(data / "helpers/launch-shell.sh"), "--explain"], env=gpu_env, text=True)
    assert "backend: opengl (Qt default)" in result, result

    check_monitors(data)
    check_environment_scopes(data, root, environment)

    for script in data.rglob("*.py"):
        compile(script.read_text(), str(script), "exec")
    for script in (data / "helpers").glob("*.sh"):
        subprocess.run(["bash", "-n", str(script)], check=True)

print(f"lucid-shell: {len(expected)} registrations, {len(expected) * 4} rendered outputs, {len(reloads) * 4} reload hooks; wallpaper and state checks passed")
