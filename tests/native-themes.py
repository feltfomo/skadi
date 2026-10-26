import json
from pathlib import Path
import re
import subprocess
import sys


root, gtk_package, qt_package, output, qt_plugins = map(Path, sys.argv[1:])
work = Path.cwd() / "native-theme-work"
work.mkdir()
output.mkdir()


def run(*arguments, **options):
    return subprocess.run([str(argument) for argument in arguments], check=True, **options)


def parse_gtk(version, *stylesheets, screenshot=None, palette=None):
    arguments = [sys.executable, root / "tests/gtk-theme.py", version, *stylesheets,
                 "--theme-package", gtk_package]
    if screenshot:
        arguments += ["--screenshot", screenshot]
    if palette:
        arguments += ["--palette", palette]
    run(*arguments)


def defines(css):
    return dict(re.findall(r"@define-color\s+(\w+)\s+([^;]+);", css))


def render_caelestia(source, palette):
    colors = {}
    for name, color in palette.items():
        parts = name.split("_")
        colors[parts[0] + "".join(part.title() for part in parts[1:])] = color.lstrip("#")
    return re.sub(r"\{\{\s*(\w+)\.hex\s*\}\}", lambda match: colors[match[1]], source)


for version in ["3.0", "4.0"]:
    directory = gtk_package / f"share/themes/Skadi/gtk-{version}"
    parse_gtk(version, directory / "gtk.css", directory / "gtk-light.css")

rendered = work / "rendered"
rendered.mkdir()
templates = [root / f"configs/gtk/reactive-gtk{version}.css" for version in [3, 4]]
templates.append(root / "configs/qt/reactive.json")
config = work / "matugen.toml"
config.write_text("[config]\nreload_apps = false\n" + "".join(
    f"\n[templates.theme{index}]\ninput_path = {json.dumps(str(source))}\n"
    f"output_path = {json.dumps(str(rendered / source.name))}\n"
    for index, source in enumerate(templates)
))

for mode in ["dark", "light"]:
    for seed in ["#89b4fa", "#de8060"]:
        run("matugen", "color", "hex", seed, "--mode", mode, "--config", config)
        palette_path = rendered / "reactive.json"
        palette = json.loads(palette_path.read_text())
        for source in templates:
            assert "{{" not in (rendered / source.name).read_text(), source
        caelestia = render_caelestia((root / "configs/qt/caelestia.json").read_text(), palette)
        assert json.loads(caelestia) == palette
        home = work / f"config-{mode}-{seed[1:]}"
        for version, number in [("3.0", 3), ("4.0", 4)]:
            directory = home / f"gtk-{version}"
            directory.mkdir(parents=True)
            source = rendered / f"reactive-gtk{number}.css"
            (directory / "reactive.css").write_text(source.read_text())
            gtk_palette = {
                name.removeprefix("skadi_"): value
                for name, value in defines(source.read_text()).items()
            }
            caelestia = render_caelestia(
                (root / f"configs/gtk/caelestia-gtk{number}.css").read_text(), gtk_palette)
            assert defines(caelestia) == defines(source.read_text())
            (directory / "gtk.css").write_text(
                '@import url("reactive.css");\n'
                '@import url("../gtk-theme/widgets.css");\n'
                '.user-rule { color: #123456; }\n')

        run(gtk_package / "bin/skadi-gtk-apply", "--config-home", home)
        before = {path: path.read_bytes() for path in home.glob("gtk-*/*.css")}
        run(gtk_package / "bin/skadi-gtk-apply", "--config-home", home)
        assert before == {path: path.read_bytes() for path in before}
        for version in ["3.0", "4.0"]:
            entry = home / f"gtk-{version}/gtk.css"
            content = entry.read_text()
            assert '.user-rule { color: #123456; }' in content
            assert content.count('@import url("skadi.css");') == 1
            parse_gtk(version, entry, screenshot=(
                output / f"gtk-{mode}-{seed[1:]}.png" if version == "3.0" else None),
                palette=home / f"gtk-{version}/reactive.css")

        run(qt_package / "bin/skadi-qt-theme", "--palette", palette_path, "--config-home", home)
        qt_files = [home / f"Kvantum/Skadi/Skadi.{suffix}" for suffix in ["svg", "kvconfig"]]
        qt_files += [home / f"qt{version}ct/colors/reactive.conf" for version in [5, 6]]
        previous = {path: path.read_bytes() for path in qt_files}
        run(qt_package / "bin/skadi-qt-theme", "--palette", palette_path, "--config-home", home)
        assert previous == {path: path.read_bytes() for path in qt_files}
        selection = home / "Kvantum/kvantum.kvconfig"
        selection.write_text("[General]\ntheme=Skadi\n")
        run(sys.executable, root / "tests/qt-theme.py", home, qt_plugins,
            output / f"qt-{mode}-{seed[1:]}.png")
        invalid = work / "invalid.json"
        invalid.write_text('{"primary": "invalid"}')
        failed = subprocess.run([
            str(qt_package / "bin/skadi-qt-theme"), "--palette", str(invalid),
            "--config-home", str(home)], capture_output=True, text=True)
        assert failed.returncode != 0
        assert previous == {path: path.read_bytes() for path in qt_files}

blocked = work / "unmanaged-gtk"
(blocked / "gtk-3.0").mkdir(parents=True)
(blocked / "gtk-4.0").mkdir()
(blocked / "gtk-3.0/gtk.css").write_text("/* existing user stylesheet */\n")
(blocked / "gtk-4.0/skadi.css").write_text("/* unmanaged stylesheet */\n")
before = {path: path.read_bytes() for path in blocked.glob("gtk-*/*.css")}
failed = subprocess.run([str(gtk_package / "bin/skadi-gtk-apply"), "--config-home", str(blocked)],
                        capture_output=True, text=True)
assert failed.returncode != 0
assert before == {path: path.read_bytes() for path in before}
assert not (blocked / "gtk-3.0/skadi.css").exists()

blocked = work / "unmanaged-qt"
(blocked / "Kvantum/Skadi").mkdir(parents=True)
(blocked / "Kvantum/Skadi/user.svg").write_text("user artwork")
failed = subprocess.run([str(qt_package / "bin/skadi-qt-theme"), "--config-home", str(blocked)],
                        capture_output=True, text=True)
assert failed.returncode != 0
assert (blocked / "Kvantum/Skadi/user.svg").read_text() == "user artwork"
assert not (blocked / "Kvantum/Skadi/Skadi.svg").exists()

print("Native theme rendering, renderer parity, idempotence, and failed publication passed")
