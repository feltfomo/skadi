# Serpantinum on Skadi

The pinned upstream flake supplies the package and NixOS support module. Skadi
uses its Quickshell input with Qt compatibility, multimedia, websocket and
image-format modules. Hyprland starts the daemon; the Home Manager service is not enabled,
so another compositor does not start this shell.

The package override routes image palettes through Lexicon's
`.config/serpantinum/matugen/config.toml`. DMS retains the default Matugen
configuration. WallpaperEngine delegates palette generation to the shell's
Matugen singleton instead of invoking the default configuration separately.
Static presets write only Serpantinum's state, leaving app palettes alone.
Thumbnail preparation writes to the cache and preserves original WebP files.

Furnish seeds `.config/serpantinum/settings.json` as writable runtime-owned
state. The seed enables wallpaper-derived colors and notifications, disables
automatic idle actions, and clears upstream's disabled `eDP-1` entry.

Bars use upstream's per-screen instances. Skadi adds `dock.screens`, a list of
connector names: empty selects every output, and an unplugged selection falls
back to the first live output. The seed selects `DP-1`, which falls back to
`eDP-1` on the laptop. The desktop daemon starts with Vulkan for its NVIDIA
driver; the laptop uses Qt's default backend.

Upstream's README licenses the project under AGPL-3.0-or-later. Its Nix package
metadata declares MIT; the override uses AGPL and installs `LICENSE.md`.

Print retains Skadi's screenshot workflow. Shell bindings use Serpantinum's
launcher, notifications, clipboard, music, guide, system and wallpaper IPC.
The keyboard overlay and direct text-capture shortcuts have no equivalent.
