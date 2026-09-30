# Lucid shell

`modules/aspects/lucid.nix` deploys this package's QML under
`~/.config/quickshell/lucid` through furnish. `lucid-shell` launches that config;
`lucid-shell-ipc TARGET ACTION` addresses the same instance. Neither command runs
the upstream Arch installer. `lucid-shell --explain` prints the GPU backend decision.

The shell owns its writable settings and dock pins. GTK, Qt and Hyprland
configuration stay managed by Skadi, so their environment-writing switches start
disabled. The keybind editor and sheet do not manage Skadi's Lua bindings.

Lexicon's `lucid` renderer collects app templates into
`~/.config/lucid/matugen/config.toml`. The shell's palette registers there too.
The wallpaper hook selects this config explicitly; DMS keeps its own config.
`lucid-wallpaper IMAGE [dark|light]` and the GUI wallpaper picker run those
registrations and their reload hooks. The Matugen theme is selected on deployment.

Static themes and Pywal update the shell palette only. Their upstream hardcoded
app writers are disabled to avoid overwriting managed configs. App templates follow
wallpaper changes in Matugen mode. SDDM stays managed by NixOS.

End4 bindings without a supported equivalent are absent. Recording remains
available in Lucid's screenshot toolbar, without a direct recording shortcut.
The Print shortcut retains Skadi's Hyprshot and Satty workflow.
