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

-- every opener (bind, bar, IPC) lands here, otherwise the window floats at its 1020x500 minimum
hl.window_rule({
	name = "noctalia-settings",
	match = { class = "^dev.noctalia.Noctalia$", title = "^Noctalia Settings$" },
	float = true,
	group = "deny",
	size = "min(monitor_w,1600) monitor_h*0.7",
	center = true,
})

-- layer surfaces can't draw their own compositor blur, so the rule sits with pinax's namespace
hl.layer_rule({
	name = "pinax",
	match = { namespace = "^pinax$" },
	blur = true,
	ignore_alpha = 0.05,
	dim_around = true,
})

-- persistent class rules survive steam's transient bootstrap windows
if G.hostname == "khion" then
	local startup_rules = {
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
