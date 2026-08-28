local G = require("globals")

-- portals use dbus activation and must not be launched from compositor startup
hl.on("hyprland.start", function()
	local commands = {
		-- the nixos hyprland module has no plugin option, so load the packaged library directly
		"hyprctl plugin list | grep -q gloview || hyprctl plugin load /run/current-system/sw/lib/libgloview.so",
		"end4-pc-shell",
		"pypr",
		"wl-paste --type text --watch cliphist store",
		"wl-paste --type image --watch cliphist store",
		"systemctl --user restart audio-opacity",
	}

	for _, command in ipairs(commands) do
		hl.exec_cmd(command)
	end

	-- persistent rules place these apps without one-shot launch properties
	-- spotify is launched lazily by its scratchpad instead
	if G.hostname == "khion" then
		for _, command in ipairs({ "zen-twilight", "equibop", "steam" }) do
			hl.exec_cmd(command)
		end
	end
end)
