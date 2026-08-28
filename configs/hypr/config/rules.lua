local G = require("globals")

-- maximize requests conflict with compositor-managed tiling
hl.window_rule({
	name = "suppress-maximize-events",
	match = { class = ".*" },
	suppress_event = "maximize",
})

-- empty xwayland drag surfaces must not steal focus
hl.window_rule({
	name = "fix-xwayland-drags",
	match = {
		class = "^$",
		title = "^$",
		xwayland = true,
		float = true,
		fullscreen = false,
		pin = false,
	},
	no_focus = true,
})

-- the launcher floats near the lower-left edge instead of inheriting the tile layout
hl.window_rule({
	name = "move-hyprland-run",
	match = { class = "hyprland-run" },
	move = "20 monitor_h-120",
	float = true,
})

-- persistent class rules survive steam's transient bootstrap windows
if G.hostname == "khion" then
	local startup_rules = {
		{ name = "startup-zen", class = "^zen-twilight$", workspace = 1 },
		{ name = "startup-equibop", class = "^equibop$", workspace = 2 },
		{ name = "startup-steam", class = "^steam$", workspace = 3 },
	}

	-- silent placement keeps startup windows from changing the focused workspace
	for _, rule in ipairs(startup_rules) do
		hl.window_rule({
			name = rule.name,
			match = { class = rule.class },
			workspace = tostring(rule.workspace) .. " silent",
		})
	end
end
