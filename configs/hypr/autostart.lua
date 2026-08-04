local G = require("globals")

hl.on("hyprland.start", function()
	hl.exec_cmd("systemctl --user reset-failed xdg-desktop-portal-hyprland")
	hl.exec_cmd("systemctl --user start xdg-desktop-portal-hyprland")
	hl.exec_cmd("caelestia shell -d")
	hl.exec_cmd("wl-paste --type text --watch cliphist store")
	hl.exec_cmd("wl-paste --type image --watch cliphist store")

	-- keep audio-playing windows undimmed while inactive (defined in aspects/hyprland.nix).
	hl.exec_cmd("systemctl --user restart audio-opacity")

	-- launch my always-open apps onto workspaces 1-4 (khion's left monitor,
	-- since workspaces 1-10 are locked to DP-1 in helpers/workspace.lua).
	if G.hostname == "khion" then
		local startup_apps = {
			{ workspace = 1, cmd = "zen-twilight" },
			{ workspace = 2, cmd = "spotify" },
			{ workspace = 3, cmd = "equibop" },
			{ workspace = 4, cmd = "steam" },
		}
		for _, app in ipairs(startup_apps) do
			hl.exec_cmd(app.cmd, { workspace = tostring(app.workspace) })
		end
	end
end)
