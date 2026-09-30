import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import tomllib


data = Path(sys.argv[1])
config = tomllib.loads(Path(sys.argv[2]).read_text())
seeds = json.loads(Path(sys.argv[3]).read_text())
settings = json.loads(Path(sys.argv[4]).read_text())
expected = {
    "bat", "btop", "cava", "firefox-chrome", "firefox-content", "fuzzel",
    "ghostty", "gtk-gtk3", "gtk-gtk4", "helix", "herdr", "hyprland", "kitty",
    "serpantinum-shell", "nvim", "qt-qt5ct", "qt-qt6ct", "zed",
}
assert set(config["templates"]) == expected, sorted(config["templates"])
assert len(seeds) == len({seed["dest"] for seed in seeds})
assert settings["display"]["monitors"] == {}
assert settings["idle"]["enabled"] is False
assert settings["dock"]["screens"] == ["DP-1"]
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
    palettes = []
    for color in ("#ff0000", "#0000ff"):
        image = root / (color[1:] + ".png")
        subprocess.run(["magick", "-size", "32x32", "xc:" + color, str(image)], check=True)
        for mode in ("dark", "light"):
            subprocess.run([
                "matugen", "-c", str(render_config), "image", str(image),
                "-m", mode, "--source-color-index", "0",
            ], check=True)
            outputs = {name: (root / "outputs" / name).read_text() for name in expected}
            assert all(text and "{{" not in text for text in outputs.values())
            palettes.append(outputs)
    assert palettes[0]["serpantinum-shell"] != palettes[1]["serpantinum-shell"]
    assert palettes[0]["serpantinum-shell"] != palettes[2]["serpantinum-shell"]
    assert palettes[0]["nvim"] != palettes[2]["nvim"]
    assert sorted(hooks.read_text().splitlines()) == sorted(list(reloads) * 4)
    assert "colorscheme reactive" in config["templates"]["nvim"]["post_hook"]
    nvim_palette = root / "nvim.lua"
    nvim_palette.write_text(palettes[0]["nvim"])
    selector = root / "select-palette.lua"
    selector.write_text('''
vim = { o = { background = arg[2] } }
local palette = dofile(arg[1])
assert(#palette.term == 16)
io.write(palette.primary, "\\n")
''')
    for index, mode in enumerate(("dark", "light")):
        primary = subprocess.check_output(["lua", str(selector), str(nvim_palette), mode], text=True).strip()
        assert primary == json.loads(palettes[index]["serpantinum-shell"])["blue"]

    home = root / "home"
    (home / ".config/serpantinum").mkdir(parents=True)
    (home / ".config/serpantinum/settings.json").write_text(json.dumps(settings))
    runtime = root / "runtime"
    runtime.mkdir()
    env = os.environ | {"HOME": str(home), "XDG_RUNTIME_DIR": str(runtime)}
    version = subprocess.check_output([str(data.parents[1] / "bin/serpantinum"), "--version"], env=env, text=True).strip()
    assert version.startswith("serpantinum v"), version
    assert "GNU AFFERO GENERAL PUBLIC LICENSE" in (data.parents[1] / "share/licenses/serpantinum/LICENSE.md").read_text()
    print(version)

    # Opening the wallpaper picker must leave source WebP images untouched.
    wallpapers = root / "wallpapers"
    wallpapers.mkdir()
    webp = wallpapers / "original.webp"
    subprocess.run(["magick", "-size", "32x32", "xc:#abcdef", str(webp)], check=True)
    original = webp.read_bytes()
    tools = root / "tools"
    tools.mkdir()
    ready = root / "thumbnail-ready"
    os.mkfifo(ready)
    thumbs = home / ".cache/serpantinum/wallpaper/thumbs"
    quickshell = tools / "quickshell"
    quickshell.write_text(f"#!{shutil.which('bash')}\nread -r result < \"$TEST_READY\"\n")
    quickshell.chmod(0o755)
    magick = tools / "magick"
    magick.write_text(f"#!{shutil.which('bash')}\n{shutil.which('magick')} \"$@\" || exit $?\n" + '''
if [[ "${@: -1}" == "$TEST_THUMBS/"* ]]; then
    printf '%s\\n' ready > "$TEST_READY"
fi
''')
    magick.chmod(0o755)
    prep_env = env | {
        "PATH": str(tools) + ":" + env["PATH"], "SERPANTINUM_DIR": str(data),
        "WALLPAPER_DIR": str(wallpapers), "TEST_READY": str(ready), "TEST_THUMBS": str(thumbs),
    }
    prep = subprocess.Popen([str(data / "scripts/qs_manager.sh"), "open", "wallpaper"],
                            env=prep_env, start_new_session=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        stdout, stderr = prep.communicate(timeout=20)
    except subprocess.TimeoutExpired:
        os.killpg(prep.pid, signal.SIGKILL)
        prep.communicate()
        raise
    assert prep.returncode == 0, (stdout, stderr)
    assert webp.read_bytes() == original
    assert not (wallpapers / "original.jpg").exists()
    assert (thumbs / "original.webp").is_file()

    # Static presets may write shell state, but not registered app outputs.
    static_config = data / "assets/matugen/config-static.toml"
    static = tomllib.loads(static_config.read_text())
    assert set(static["templates"]) == {"quickshell"}
    sentinel = home / ".config/cava/config"
    sentinel.parent.mkdir()
    sentinel.write_text("managed cava\n")
    template = (data / "assets/matugen/templates/serpantinum_matugen_colors.json.template").read_text()
    roles = set(re.findall(r"colors\.([^.]+)\.default\.hex", template))
    synthetic = root / "synthetic.json"
    synthetic.write_text(json.dumps({"colors": {
        role: {mode: {"hex": "#112233", "color": "#112233"} for mode in ("default", "dark", "light")}
        for role in roles
    }}))
    subprocess.run(["matugen", "-c", str(static_config), "json", str(synthetic)], env=env, cwd=data / "assets/matugen", check=True)
    assert sentinel.read_text() == "managed cava\n"
    palette = home / ".local/state/serpantinum/qs_matugen_colors.json"
    assert json.loads(palette.read_text())["blue"] == "#112233"

    dock = (data / "quickshell/dock/Dock.qml").read_text()
    model = re.search(r"^    model: \{(.*?)^    \}", dock, re.M | re.S)
    assert model
    matugen = (data / "quickshell/singletons/theme/Matugen.qml").read_text()
    generate = re.search(r"^    function _startImageGenerate\(.*?^    \}", matugen, re.M | re.S)
    assert generate
    config_expression = re.search(r"property string configPath: (.*)", matugen)[1]
    script = '''
const assert = require("node:assert/strict");
const Quickshell = {screens: [{name: "DP-1"}, {name: "DP-2"}], env: () => "/home/test"};
let selected = ["DP-1"];
const Config = {getSetting: () => ({screens: selected})};
function dockScreens() { MODEL }
assert.deepEqual(dockScreens().map(s => s.name), ["DP-1"]);
selected = [];
assert.deepEqual(dockScreens().map(s => s.name), ["DP-1", "DP-2"]);
selected = ["DP-1"];
Quickshell.screens = [{name: "eDP-1"}];
assert.deepEqual(dockScreens().map(s => s.name), ["eDP-1"]);
const root = {configPath: CONFIG, generationStarted: () => {}};
const matugenProcess = {};
GENERATE
_startImageGenerate("/wallpaper with spaces.png", "light", "scheme-tonal-spot");
assert.deepEqual(matugenProcess.command, [
    "matugen", "image", "/wallpaper with spaces.png",
    "-c", "/home/test/.config/serpantinum/matugen/config.toml",
    "-m", "light", "-t", "scheme-tonal-spot", "--source-color-index", "0"
]);
'''.replace("MODEL", model[1]).replace("CONFIG", config_expression).replace("GENERATE", generate[0])
    subprocess.run(["node", "-e", script], check=True)
    engine = (data / "quickshell/wallpaper/WallpaperEngine.qml").read_text()
    assert "matugen image" not in engine
    assert "Matugen.generate(cleanPath)" in engine
    assert "model: Quickshell.screens" in (data / "quickshell/bar/Bar.qml").read_text()
    for source in data.rglob("*.py"):
        compile(source.read_text(), str(source), "exec")
    for source in data.rglob("*.sh"):
        subprocess.run(["bash", "-n", str(source)], check=True)

print(f"serpantinum: {len(expected)} registrations, {len(expected) * 4} rendered outputs, {len(reloads) * 4} reload hooks; private config, static palette, WebP preservation and dock routing checks passed")
