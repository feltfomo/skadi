import argparse
import os
from pathlib import Path
import re

import gi


arguments = argparse.ArgumentParser()
arguments.add_argument("version", choices=["3.0", "4.0"])
arguments.add_argument("stylesheets", nargs="+")
arguments.add_argument("--screenshot", type=Path)
arguments.add_argument("--palette", type=Path)
arguments.add_argument("--theme-package", type=Path)
options = arguments.parse_args()
version, stylesheets = options.version, options.stylesheets
if options.theme_package:
    os.environ["XDG_DATA_DIRS"] = str(options.theme_package / "share") + ":" + os.environ.get(
        "XDG_DATA_DIRS", "/usr/local/share:/usr/share")
gi.require_version("Gtk", version)
from gi.repository import Gtk


if version == "3.0":
    Gtk.init([])
else:
    Gtk.init()
    gi.require_version("Adw", "1")
    from gi.repository import Adw

    Adw.init()
settings = Gtk.Settings.get_default()
if version == "3.0" and options.theme_package:
    settings.set_property("gtk-theme-name", "Skadi")

for stylesheet in stylesheets:
    errors = []
    provider = Gtk.CssProvider()
    provider.connect("parsing-error", lambda provider, section, error: errors.append(str(error)))
    provider.load_from_path(str(Path(stylesheet).resolve()))
    assert not errors, (stylesheet, errors)

if options.palette:
    from gi.repository import Gdk

    if version == "3.0":
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_USER)
    else:
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_USER)
    window = Gtk.Window()
    context = window.get_style_context()
    colors = dict(re.findall(r"@define-color\s+(\w+)\s+(#[0-9a-fA-F]{6});",
                             options.palette.read_text()))

    def rgb(name):
        value = colors[name]
        return tuple(int(value[index:index + 2], 16) / 255 for index in [1, 3, 5])

    expected = {
        "accent_bg_color": rgb("skadi_primary"),
        "accent_fg_color": rgb("skadi_on_primary"),
        "window_fg_color": rgb("skadi_on_surface"),
        "window_bg_color": tuple(a * 0.08 + b * 0.92 for a, b in zip(
            rgb("skadi_primary"), rgb("skadi_surface_container_low"))),
    }
    for name, components in expected.items():
        found, color = context.lookup_color(name)
        assert found, name
        actual = [color.red, color.green, color.blue]
        assert all(abs(a - b) < 1 / 255 for a, b in zip(actual, components)), (name, actual, components)
    if version == "3.0":
        settings.set_property("gtk-theme-name", "HighContrast")
        assert not context.lookup_color("skadi_shell")[0]
        with_palette = context.get_background_color(Gtk.StateFlags.NORMAL).to_string()
        Gtk.StyleContext.remove_provider_for_screen(Gdk.Screen.get_default(), provider)
        baseline = context.get_background_color(Gtk.StateFlags.NORMAL).to_string()
        assert with_palette == baseline, (with_palette, baseline)
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_USER)
        settings.set_property("gtk-theme-name", "Skadi")
    window.destroy()

if options.screenshot:
    assert version == "3.0"
    from gi.repository import Gdk

    Gtk.StyleContext.add_provider_for_screen(
        Gdk.Screen.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_USER)
    window = Gtk.Window(title="Skadi widget gallery")
    grid = Gtk.Grid(column_spacing=12, row_spacing=12, margin=16)
    window.add(grid)
    entry = Gtk.Entry(text="Editable field")
    grid.attach(entry, 0, 0, 2, 1)
    grid.attach(Gtk.Button(label="Ordinary button"), 0, 1, 1, 1)
    selected = Gtk.ToggleButton(label="Selected button", active=True)
    grid.attach(selected, 1, 1, 1, 1)
    disabled = Gtk.Button(label="Disabled button", sensitive=False)
    grid.attach(disabled, 0, 2, 1, 1)
    check = Gtk.CheckButton(label="Checked", active=True)
    grid.attach(check, 1, 2, 1, 1)
    grid.attach(Gtk.Switch(active=True, halign=Gtk.Align.START), 0, 3, 1, 1)
    radio = Gtk.RadioButton(label="Selected", active=True)
    grid.attach(radio, 1, 3, 1, 1)
    scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0, 100, 1)
    scale.set_value(60)
    grid.attach(scale, 0, 4, 2, 1)
    grid.attach(Gtk.ProgressBar(fraction=0.6), 0, 5, 2, 1)
    rows = Gtk.ListBox(selection_mode=Gtk.SelectionMode.SINGLE)
    for name in ["Selected row with hovered button", "Ordinary row"]:
        row = Gtk.ListBoxRow()
        box = Gtk.Box(spacing=12, margin=8)
        box.pack_start(Gtk.Label(label=name, xalign=0), True, True, 0)
        button = Gtk.Button.new_from_icon_name("window-close-symbolic", Gtk.IconSize.BUTTON)
        button.get_style_context().add_class("flat")
        box.pack_end(button, False, False, 0)
        row.add(box)
        rows.add(row)
        if rows.get_row_at_index(0) == row:
            rows.select_row(row)
            button.set_state_flags(Gtk.StateFlags.PRELIGHT, False)
    grid.attach(rows, 0, 6, 2, 1)
    notebook = Gtk.Notebook()
    notebook.append_page(Gtk.Label(label="Tab content", margin=20), Gtk.Label(label="Selected tab"))
    notebook.append_page(Gtk.Label(label="Other content"), Gtk.Label(label="Other tab"))
    grid.attach(notebook, 0, 7, 2, 1)
    window.set_default_size(560, 600)
    window.show_all()
    entry.grab_focus()
    from gi.repository import GLib

    painted = GLib.MainLoop()
    window.get_frame_clock().connect("after-paint", lambda clock: painted.quit())
    painted.run()
    window.get_display().sync()
    image = Gdk.pixbuf_get_from_window(
        window.get_window(), 0, 0, window.get_allocated_width(), window.get_allocated_height())
    assert image is not None
    image.savev(str(options.screenshot), "png", [], [])
    window.destroy()

print(f"GTK {version} parsed {len(stylesheets)} theme entrypoints without diagnostics")
