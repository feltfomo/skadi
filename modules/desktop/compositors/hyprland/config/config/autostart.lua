local G = require("globals")

-- portals use dbus activation and must not be launched from compositor startup
hl.on("hyprland.start", function()
	local commands = {
		"wl-paste --type image --watch cliphist store",
		"wl-paste --type text --watch cliphist store",
		"systemctl --user restart audio-opacity",
		"systemctl --user restart pinax",
		"noctalia-session hyprland",
		"pypr",
	}

	for _, command in ipairs(commands) do
		hl.exec_cmd(command)
	end

	-- spotify is launched lazily by its scratchpad instead
	if G.hostname == "khion" then
		-- a launch rule is spent on the first window, so later zen windows open where they're asked for
		hl.exec_cmd("zen-twilight", { workspace = "1 silent" })

		-- persistent rules in rules.lua place these
		for _, command in ipairs({ "equibop", "steam" }) do
			hl.exec_cmd(command)
		end
	end
end)
