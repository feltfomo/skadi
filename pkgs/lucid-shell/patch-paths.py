"""Keep Lucid's writable state separate from other Quickshell configurations."""

import pathlib
import sys

root = pathlib.Path(sys.argv[1])
sounds, emoji = sys.argv[2:]

for path in root.rglob("*"):
    if path.suffix not in {".qml", ".sh", ".py"}:
        continue
    text = path.read_text()
    text = text.replace("/.config/quickshell/", "/.config/quickshell/lucid/")
    text = text.replace("/usr/share/sounds/freedesktop", sounds + "/share/sounds/freedesktop")
    text = text.replace("/usr/share/fonts/noto/NotoColorEmoji.ttf", emoji + "/share/fonts/noto/NotoColorEmoji.ttf")
    for directory in ("applications", "icons", "themes"):
        text = text.replace("/usr/share/" + directory, "/run/current-system/sw/share/" + directory)
    if path.name == "Dock.qml":
        text = text.replace(
            "/run/current-system/sw/share/applications",
            "/run/current-system/sw/share/applications $HOME/.nix-profile/share/applications /etc/profiles/per-user/$USER/share/applications",
        )
        text = text.replace(
            "/run/current-system/sw/share/icons",
            "/run/current-system/sw/share/icons $HOME/.nix-profile/share/icons /etc/profiles/per-user/$USER/share/icons",
        )
    if path.name == "resolve-icons.sh":
        text = text.replace(
            "/run/current-system/sw/share/icons",
            "/run/current-system/sw/share/icons $HOME/.nix-profile/share/icons /etc/profiles/per-user/$USER/share/icons",
        )
    if path.name in {"envtool.py", "cursorshadow.py"}:
        for directory in ("icons", "themes"):
            text = text.replace(
                '"/run/current-system/sw/share/' + directory + '"',
                '"/run/current-system/sw/share/' + directory + '", '
                + 'f"{HOME}/.nix-profile/share/' + directory + '", '
                + 'f"/etc/profiles/per-user/{os.environ.get(\'USER\', \'\')}/share/' + directory + '"',
            )
    if path.name == "Mpris.qml":
        text = text.replace("/.config/cava/quickshell.conf", "/.config/cava/lucid.conf")
    if path.name == "Monitors.qml":
        replacements = (
            (
                """    // a description outlives the port it was plugged into, so it is the key
    function keyFor(name, description) {
        const d = String(description || "").trim();
        return d !== "" ? "desc:" + d : String(name);
    }""",
                """    // Identical EDIDs can give different outputs the same description.
    // Only unique descriptions can identify a display independently of its port.
    function keyFor(name, description, outputs) {
        const d = String(description || "").trim();
        const monitors = outputs || (root.probed ? root.outputs : Hyprland.monitors.values);
        const matches = monitors.filter((m) => String(m.description || "").trim() === d);
        return d !== "" && matches.length <= 1 ? "desc:" + d : String(name);
    }""",
            ),
            (
                "                    for (const m of JSON.parse(this.text)) {",
                "                    const monitors = JSON.parse(this.text);\n                    for (const m of monitors) {",
            ),
            (
                '"key": root.keyFor(m.name, m.description),',
                '"key": root.keyFor(m.name, m.description, monitors),',
            ),
        )
        for before, after in replacements:
            if text.count(before) != 1:
                raise ValueError("cannot locate monitor identity mapping")
            text = text.replace(before, after)
    if path.name == "envtool.py":
        # Toolkit switches also govern shared settings and live cursor updates.
        start = text.index("def apply(cfg):")
        head, body = text[:start], text[start:]
        for before, after in (
            ("    if cursor:\n", "    if (scope_gtk or scope_qt) and cursor:\n"),
            ('    if have("gsettings"):\n', '    if scope_gtk and have("gsettings"):\n'),
            (
                '    if cursor and csize and have("hyprctl"):\n',
                '    if scope_hypr and cursor and csize and have("hyprctl"):\n',
            ),
        ):
            if body.count(before) != 1:
                raise ValueError("cannot locate environment scope guard")
            body = body.replace(before, after)
        text = head + body
    if path.name == "launch-shell.sh":
        # NVIDIA's open module includes the architecture before its version.
        before = "Kernel Module *"
        if text.count(before) != 1:
            raise ValueError("cannot locate NVIDIA driver version parser")
        text = text.replace(before, "Kernel Module.* ")
    if path.name == "set-wallpaper.sh":
        before = 'matugen image "$WALLPAPER"'
        if text.count(before) != 1:
            raise ValueError("cannot locate wallpaper palette generator")
        text = text.replace(before, 'matugen -c "$LUCID_DIR/matugen/config.toml" image "$WALLPAPER"')
    if path.name == "apply-theme.sh":
        # Static palettes and Pywal may update the shell, but app files belong
        # to the registered templates, not upstream's hardcoded app writers.
        start = "set -euo pipefail\n"
        end = "if ! command -v jq"
        if text.count(start) != 1 or text.count(end) != 1:
            raise ValueError("cannot locate static palette validation")
        text = "#!/usr/bin/env bash\n# App palettes belong to the registered templates.\n\n" + text[text.index(start):text.index(end)]
        text += 'mkdir -p "$HOME/.cache/quickshell"\n'
        text += 'cp "$PALETTE" "$HOME/.cache/quickshell/matugen.json"\n'
        text += 'echo "applied theme \'$THEME\' (shell palette)"\n'
    if path.name == "sync-sddm.sh":
        text = "#!/usr/bin/env bash\n# The display manager theme belongs to NixOS.\nexit 0\n"
    if path.name == "Glass.qml":
        before = 'cp \\"$f\\" \\"$f.pre-lucid-glass\\";'
        if text.count(before) != 1:
            raise ValueError("cannot locate kitty glass include writer")
        text = text.replace(before, '[ -L \\"$f\\" ] && { echo no; exit 0; };' + before)
    path.write_text(text)
