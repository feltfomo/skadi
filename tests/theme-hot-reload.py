import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import time


parser = argparse.ArgumentParser()
parser.add_argument("toolkit", choices=["gtk", "qt"])
parser.add_argument("version")
parser.add_argument("root", type=Path)
parser.add_argument("gtk_theme", type=Path)
parser.add_argument("qt_theme", type=Path)
parser.add_argument("output", type=Path)
parser.add_argument("--gtk-reload", type=Path)
parser.add_argument("--qt-plugins", type=Path)
parser.add_argument("--qt-platform-plugins", type=Path)
parser.add_argument("--replace-style", action="store_true")
args = parser.parse_args()
suffix = "-replace-style" if args.replace_style else ""
work = Path.cwd() / f"hot-reload-{args.toolkit}-{args.version}{suffix}"
work.mkdir()
home = work / "config"
home.mkdir()
args.output.mkdir(parents=True, exist_ok=True)
os.environ["XDG_CONFIG_HOME"] = str(home)
os.environ.pop("GTK_THEME", None)
os.environ.pop("GTK_MODULES", None)
os.environ.pop("GTK_PATH", None)
os.environ.pop("QT_QPA_PLATFORMTHEME", None)
os.environ.pop("QT_STYLE_OVERRIDE", None)
os.environ["QT_QPA_PLATFORM"] = "offscreen"
os.environ["QT_SCALE_FACTOR"] = "1"
os.environ["GSK_RENDERER"] = "cairo"
gtk_module = "libskadi-palette-reload.so"
if args.gtk_reload and args.toolkit == "gtk" and args.version == "3.0":
    os.environ["GTK_MODULES"] = str(args.gtk_reload / "lib/gtk-3.0/modules" / gtk_module)
if args.gtk_reload and args.toolkit == "gtk" and args.version == "4.0":
    os.environ["GTK_PATH"] = str(args.gtk_reload / "lib/gtk-4.0")
os.environ["XDG_DATA_DIRS"] = str(args.gtk_theme / "share") + ":" + os.environ.get("XDG_DATA_DIRS", "")


def run(*arguments):
    return subprocess.run([str(argument) for argument in arguments], check=True, capture_output=True, text=True)


def raw_colors(name):
    source = args.root / f"configs/gtk/theme/palette-{name}.css"
    return dict(re.findall(r"@define-color\s+skadi_(\w+)\s+(#[0-9a-fA-F]{6});", source.read_text()))


initial = raw_colors("dark")
warm = initial | {
    "primary": "#d8bb8a", "on_primary": "#3c2c10", "on_surface": "#eee4d9",
    "surface_container_low": "#292323", "surface_container": "#302828",
    "surface_container_high": "#3a3232", "outline_variant": "#65524a",
}
light = raw_colors("light")


def css(colors):
    return "".join(f"@define-color skadi_{name} {color};\n" for name, color in colors.items())


def replace(path, content):
    temporary = path.with_name(path.name + ".next")
    if isinstance(content, bytes):
        temporary.write_bytes(content)
    else:
        temporary.write_text(content)
    temporary.replace(path)


def rgb(value):
    return tuple(int(value[index:index + 2], 16) / 255 for index in [1, 3, 5])


def shell(colors):
    return tuple(a * 0.08 + b * 0.92 for a, b in zip(
        rgb(colors["primary"]), rgb(colors["surface_container_low"])))


def close(first, second):
    return all(abs(a - b) < 1 / 255 for a, b in zip(first, second))


for version in ["3.0", "4.0"]:
    directory = home / f"gtk-{version}"
    directory.mkdir()
    (directory / "reactive.css").write_text(css(initial))
run(args.gtk_theme / "bin/skadi-gtk-apply", "--config-home", home)
qt_tokens = json.loads((args.root / "configs/qt/fallback.json").read_text()).keys()


def publish_qt(colors):
    palette = work / "palette.json"
    replace(palette, json.dumps({name: colors[name] for name in qt_tokens}))
    run(args.qt_theme / "bin/skadi-qt-theme", "--palette", palette, "--config-home", home)


def invalid_qt_generation():
    theme = home / "Kvantum/Skadi"
    bad = home / "qt-theme/generations/invalid-svg"
    bad.mkdir()
    (bad / "Skadi.kvconfig").write_bytes((theme / "Skadi.kvconfig").read_bytes())
    (bad / "Skadi.svg").write_text("<svg>")
    pending = theme.with_name(".Skadi-test-next")
    pending.symlink_to(bad)
    pending.replace(theme)


publish_qt(initial)
(home / "Kvantum/kvantum.kvconfig").write_text("[General]\ntheme=Skadi\n")
pid = os.getpid()
report = {"toolkit": args.toolkit, "version": args.version, "pid": pid, "transitions": []}

if args.toolkit == "gtk":
    import gi

    gi.require_version("Gtk", args.version)
    gi.require_version("Gdk", args.version)
    from gi.repository import Gdk, GLib, Gtk

    if args.version == "3.0":
        Gtk.init([])
        Gtk.Settings.get_default().set_property("gtk-theme-name", "Skadi")
        window = Gtk.Window(title="Skadi live reload")
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        attach = lambda parent, child: parent.pack_start(child, True, True, 0)
        window.add(box)
    else:
        Gtk.init()
        gi.require_version("Adw", "1")
        from gi.repository import Adw

        Adw.init()
        Adw.StyleManager.get_default().set_color_scheme(Adw.ColorScheme.FORCE_DARK)
        window = Adw.Window(title="Skadi live reload")
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        attach = lambda parent, child: parent.append(child)
        window.set_content(box)
    entry = Gtk.Entry()
    entry.set_text("keep this edited text")
    attach(box, entry)
    rows = Gtk.ListBox()
    for index in range(100):
        row = Gtk.ListBoxRow()
        label = Gtk.Label(label=f"Row {index}")
        if args.version == "3.0":
            row.add(label)
            rows.add(row)
        else:
            row.set_child(label)
            rows.append(row)
    selected = rows.get_row_at_index(8)
    rows.select_row(selected)
    scroller = Gtk.ScrolledWindow()
    if args.version == "3.0":
        scroller.add(rows)
    else:
        scroller.set_child(rows)
        scroller.set_vexpand(True)
    attach(box, scroller)
    window.set_default_size(560, 600)
    if args.version == "3.0":
        window.show_all()
    else:
        window.present()
    loop = GLib.MainLoop()
    state = {"phase": "start", "deadline": time.monotonic() + 12, "error": None}
    context = window.get_style_context()
    watched = home / f"gtk-{args.version}/reactive.css"

    def current(colors):
        foreground = context.get_color(Gtk.StateFlags.NORMAL) if args.version == "3.0" else window.get_color()
        if not close((foreground.red, foreground.green, foreground.blue), rgb(colors["on_surface"])):
            return False
        found, accent = context.lookup_color("skadi_primary")
        if not found or not close((accent.red, accent.green, accent.blue), rgb(colors["primary"])):
            return False
        if args.version == "3.0":
            background = context.get_background_color(Gtk.StateFlags.NORMAL)
            return close((background.red, background.green, background.blue), shell(colors))
        return True

    def snapshot():
        return (window.get_focus(), entry.get_text(), entry.get_position(), entry.get_selection_bounds(),
                rows.get_selected_row(), scroller.get_vadjustment().get_value(),
                window.get_allocated_width(), window.get_allocated_height())

    def stable():
        assert snapshot() == state["snapshot"], (snapshot(), state["snapshot"])
        assert os.getpid() == pid
        if args.version == "4.0":
            assert Adw.StyleManager.get_default().get_dark()

    def tick():
        try:
            assert time.monotonic() < state["deadline"], f"GTK {args.version} timed out in {state['phase']}"
            if state["phase"] == "start":
                assert current(initial), "initial GTK palette did not load"
                entry.grab_focus()
                entry.select_region(2, 7)
                scroller.get_vadjustment().set_value(300)
                state.update(phase="ready", settle=time.monotonic() + 0.15)
            elif state["phase"] == "ready" and time.monotonic() >= state["settle"]:
                state["snapshot"] = snapshot()
                assert state["snapshot"][0] is not None
                assert state["snapshot"][3]
                assert state["snapshot"][5] > 0
                replace(watched, css(warm))
                state["phase"] = "warm"
            elif state["phase"] == "warm" and current(warm):
                stable()
                report["transitions"].append("warm")
                replace(watched, "button { color: ;")
                state.update(phase="invalid", settle=time.monotonic() + 0.6)
            elif state["phase"] == "invalid" and time.monotonic() >= state["settle"]:
                assert current(warm), "invalid CSS replaced the last working palette"
                stable()
                replace(watched, b"\xff\xfe\x00")
                state.update(phase="invalid-encoding", settle=time.monotonic() + 0.6)
            elif state["phase"] == "invalid-encoding" and time.monotonic() >= state["settle"]:
                assert current(warm), "invalid encoding replaced the last working palette"
                stable()
                replace(watched, css(light))
                state["phase"] = "light"
            elif state["phase"] == "light" and current(light):
                stable()
                report["transitions"].append("light")
                if args.version == "3.0":
                    Gtk.Settings.get_default().set_property("gtk-theme-name", "HighContrast")
                    state.update(phase="contrast-ready", settle=time.monotonic() + 0.15)
                    return True
                loop.quit()
                return False
            elif state["phase"] == "contrast-ready" and time.monotonic() >= state["settle"]:
                assert not context.lookup_color("skadi_shell")[0]
                state["contrast"] = context.get_background_color(Gtk.StateFlags.NORMAL).to_string()
                replace(watched, css(warm))
                state["phase"] = "contrast"
            elif state["phase"] == "contrast":
                found, accent = context.lookup_color("skadi_primary")
                if found and close((accent.red, accent.green, accent.blue), rgb(warm["primary"])):
                    assert not context.lookup_color("skadi_shell")[0]
                    assert context.get_background_color(Gtk.StateFlags.NORMAL).to_string() == state["contrast"]
                    report["transitions"].append("high-contrast")
                    loop.quit()
                    return False
            return True
        except Exception as error:
            state["error"] = error
            loop.quit()
            return False

    GLib.timeout_add(50, tick)
    loop.run()
    window.destroy()
    if state["error"]:
        raise state["error"]
    mapped = {line.split()[-1] for line in Path("/proc/self/maps").read_text().splitlines()
              if line.split()[-1].startswith("/")}
    modules = sorted(path for path in mapped if path.endswith("/" + gtk_module))
    assert len(modules) == 1, modules
    report["reload_module"] = modules[0]
    if args.version == "4.0":
        # the module must bind to the application's GTK rather than load a second copy.
        libraries = sorted(path for path in mapped if "/libgtk-4.so" in path)
        assert len(libraries) == 1, libraries
        report["gtk_libraries"] = libraries
else:
    from importlib import import_module

    qt = "PyQt6" if args.version == "6" else "PyQt5"
    QtCore = import_module(qt + ".QtCore")
    QtGui = import_module(qt + ".QtGui")
    QtWidgets = import_module(qt + ".QtWidgets")
    os.environ["QT_QPA_PLATFORM_PLUGIN_PATH"] = str(args.qt_platform_plugins / "platforms")
    QtWidgets.QApplication.addLibraryPath(str(args.qt_platform_plugins))
    QtWidgets.QApplication.addLibraryPath(str(args.qt_plugins))
    app = QtWidgets.QApplication([])
    style = QtWidgets.QStyleFactory.create("kvantum")
    assert style is not None, QtWidgets.QStyleFactory.keys()
    app.setStyle(style)
    roles = QtGui.QPalette.ColorRole if args.version == "6" else QtGui.QPalette
    custom = app.palette()
    custom.setColor(roles.BrightText, QtGui.QColor("#f012ac"))
    app.setPalette(custom)
    window = QtWidgets.QWidget()
    layout = QtWidgets.QVBoxLayout(window)
    entry = QtWidgets.QLineEdit("keep this edited text")
    layout.addWidget(entry)
    status = QtWidgets.QLabel("Application-owned status color")
    status_palette = status.palette()
    status_palette.setColor(roles.WindowText, QtGui.QColor("#f012ac"))
    status.setPalette(status_palette)
    layout.addWidget(status)
    button = QtWidgets.QPushButton("Selected action")
    button.setCheckable(True)
    button.setChecked(True)
    button.setMinimumHeight(40)
    layout.addWidget(button)
    rows = QtWidgets.QListWidget()
    rows.addItems([f"Row {index}" for index in range(100)])
    rows.setCurrentRow(8)
    layout.addWidget(rows)
    window.resize(560, 600)
    window.show()
    state = {"phase": "start", "deadline": time.monotonic() + 12, "error": None,
             "status_color": "#f012ac"}

    def current(colors):
        expected = "#" + "".join(f"{round(value * 255):02x}" for value in shell(colors))
        image = button.grab().toImage()
        state["colors"] = {
            "window": window.palette().color(roles.Window).name(), "expected_window": expected,
            "button": image.pixelColor(10, image.height() // 2).name(),
            "expected_button": colors["primary"],
        }
        return (state["colors"]["window"] == expected
                and state["colors"]["button"] == colors["primary"])

    def snapshot():
        return (app.style(), app.focusWidget(), entry.text(), entry.cursorPosition(), entry.selectionStart(),
                entry.selectedText(), rows.currentItem(), rows.verticalScrollBar().value(), window.size())

    def stable():
        assert snapshot() == state["snapshot"], (snapshot(), state["snapshot"])
        assert app.style() is style
        assert os.getpid() == pid
        assert app.palette().color(roles.BrightText).name() == "#f012ac"
        assert state["status_color"] == "#0ccabc"
        assert status.palette().color(roles.WindowText).name() == state["status_color"]

    if args.replace_style:
        expected = "#" + "".join(f"{round(value * 255):02x}" for value in shell(warm))

        def replace_style(palette):
            if palette.color(roles.Window).name() == expected and not state.get("switched"):
                state["switched"] = True
                app.setStyle("fusion")

        app.paletteChanged.connect(replace_style)
    else:
        expected = "#" + "".join(f"{round(value * 255):02x}" for value in shell(warm))

        def customize_status(palette):
            if palette.color(roles.Window).name() == expected:
                state["status_color"] = "#0ccabc"
                custom = status.palette()
                custom.setColor(roles.WindowText, QtGui.QColor(state["status_color"]))
                status.setPalette(custom)

        app.paletteChanged.connect(customize_status)

    def timeout_details():
        return {
            "colors": state.get("colors"),
            "watchers": [watcher.directories() for watcher in style.findChildren(QtCore.QFileSystemWatcher)],
        }

    def tick():
        try:
            assert time.monotonic() < state["deadline"], (
                f"Qt {args.version} timed out in {state['phase']}: {timeout_details()}")
            if state["phase"] == "start":
                assert current(initial), "initial Qt palette/artwork did not load"
                entry.setFocus()
                entry.setSelection(2, 5)
                rows.verticalScrollBar().setValue(30)
                state.update(phase="ready", settle=time.monotonic() + 0.15)
            elif state["phase"] == "ready" and time.monotonic() >= state["settle"]:
                state["snapshot"] = snapshot()
                assert state["snapshot"][1] is entry
                assert state["snapshot"][5] == entry.text()[2:7]
                assert state["snapshot"][7] > 0
                publish_qt(warm)
                state["phase"] = "warm"
            elif state["phase"] == "warm" and args.replace_style and state.get("switched"):
                assert app.style().objectName().lower() == "fusion"
                assert entry.text() == "keep this edited text"
                assert status.palette().color(roles.WindowText).name() == "#f012ac"
                report["transitions"].append("style-replaced")
                app.quit()
            elif state["phase"] == "warm" and current(warm):
                stable()
                report["transitions"].append("warm")
                window.grab().save(str(args.output / f"qt{args.version}-warm.png"))
                invalid_qt_generation()
                state.update(phase="invalid", settle=time.monotonic() + 0.6)
            elif state["phase"] == "invalid" and time.monotonic() >= state["settle"]:
                assert current(warm), "invalid SVG replaced the last working artwork"
                stable()
                publish_qt(light)
                state["phase"] = "light"
            elif state["phase"] == "light" and current(light):
                stable()
                report["transitions"].append("light")
                window.grab().save(str(args.output / f"qt{args.version}-light.png"))
                app.quit()
        except Exception as error:
            state["error"] = error
            app.quit()

    timer = QtCore.QTimer()
    timer.timeout.connect(tick)
    timer.start(50)
    app.exec() if args.version == "6" else app.exec_()
    if state["error"]:
        raise state["error"]

expected_transitions = ["warm", "light"]
if args.replace_style:
    expected_transitions = ["style-replaced"]
if args.toolkit == "gtk" and args.version == "3.0":
    expected_transitions.append("high-contrast")
assert report["transitions"] == expected_transitions, report
(args.output / f"{args.toolkit}{args.version}{suffix}.json").write_text(json.dumps(report, indent=2) + "\n")
if args.replace_style:
    print(f"Qt {args.version}: style replacement during live reload passed")
else:
    print(f"{args.toolkit} {args.version}: live colors, invalid-output recovery, focus, selection and scroll passed")
