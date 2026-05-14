-- autostart
hl.on("hyprland.start", function()
    hl.exec_cmd("noctalia-shell")
    hl.exec_cmd(
    "sleep 1 && hyprctl eval 'hl.monitor({ output = \"DP-2\", mode = \"2560x1440@180\", position = \"2561x0\", scale = 1 })' && sleep 0.1 && hyprctl eval 'hl.monitor({ output = \"DP-2\", mode = \"2560x1440@180\", position = \"2560x0\", scale = 1 })'")
end)
