"""Route Serpantinum's palette generation through registered app templates."""

from pathlib import Path
import re
import sys

root = Path(sys.argv[1])


def replace(relative, before, after):
    path = root / relative
    text = path.read_text()
    if text.count(before) != 1:
        raise ValueError(f"cannot locate runtime integration in {relative}")
    path.write_text(text.replace(before, after))


replace(
    "src/quickshell/singletons/theme/Matugen.qml",
    'property string configPath: matugenBaseDir + "/config.toml"',
    'property string configPath: Quickshell.env("HOME") + "/.config/serpantinum/matugen/config.toml"',
)

# Static presets write the shell palette directly. Their synthetic MD3 render
# must not overwrite app configurations owned by the registered templates.
(root / "src/assets/matugen/config-static.toml").write_text('''[config]
reload_apps = false

[templates.quickshell]
input_path = "templates/serpantinum_matugen_colors.json.template"
output_path = "~/.local/state/serpantinum/qs_matugen_colors.json"
''')

# WallpaperEngine also calls Matugen.generate, which owns the selected mode,
# scheme and config. Its shell commands must not invoke DMS's default config.
path = root / "src/quickshell/wallpaper/WallpaperEngine.qml"
text = path.read_text()
text, count = re.subn(
    r'; if command -v matugen .*?; fi; if \[ -n .*?; fi",',
    '",',
    text,
)
if count != 1:
    raise ValueError("cannot locate video wallpaper palette writer")
text, count = re.subn(
    r'                    let matugenBash = vid \? "" : \(.*?\n                    \);',
    '                    let matugenBash = "";',
    text,
    flags=re.S,
)
if count != 1:
    raise ValueError("cannot locate image wallpaper palette writer")
path.write_text(text)

# Discover WebP inputs without converting and deleting the source wallpapers.
replace(
    "src/scripts/qs_manager.sh",
    '-iname "*.jpeg" -o -iname "*.png"',
    '-iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp"',
)
replace(
    "src/scripts/qs_manager.sh",
    '''            if [[ "${extension,,}" == "webp" ]]; then
                new_img="${img%.*}.jpg"
                magick "$img" "$new_img" && rm -f "$img"
                img="$new_img"
                filename="$(basename "$img")"
                extension="jpg"
            fi

''',
    "",
)

replace(
    "src/quickshell/dock/Dock.qml",
    "    model: Quickshell.screens",
    '''    // Empty selects every output; an unplugged selection falls back to one.
    model: {
        const names = Config.getSetting("dock", {}).screens || [];
        if (names.length === 0)
            return Quickshell.screens;
        const selected = Quickshell.screens.filter((screen) => names.includes(screen.name));
        return selected.length > 0 ? selected : Quickshell.screens.slice(0, 1);
    }''',
)
