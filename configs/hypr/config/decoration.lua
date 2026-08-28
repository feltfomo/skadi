-- the live palette may not exist before the shell has started once
local ok, colors = pcall(require, "colors")
if not ok then
	colors = {
		primary = "rgb(89b4fa)",
		outline = "rgb(6c7086)",
		outline_variant = "rgb(45475a)",
		shadow_alpha = "rgba(000000aa)",
	}
end

hl.config({
	general = {
		gaps_in = 5,
		gaps_out = 15,
		border_size = 2,
		layout = "dwindle",
		col = {
			active_border = colors.primary,
			inactive_border = colors.outline_variant or colors.outline,
		},
	},
	decoration = {
		rounding = 10,
		rounding_power = 4,
		active_opacity = 0.85,
		inactive_opacity = 0.85,
		blur = {
			enabled = true,
			size = 15,
			passes = 2,
			new_optimizations = true,
		},
		shadow = {
			enabled = true,
			range = 20,
			render_power = 4,
			color = colors.shadow_alpha,
		},
	},
	animations = {
		enabled = true,
	},
})

hl.curve("easeOutQuint", { type = "bezier", points = { { 0.23, 1 }, { 0.32, 1 } } })
hl.curve("easeInOutCubic", { type = "bezier", points = { { 0.65, 0.05 }, { 0.36, 1 } } })
hl.curve("linear", { type = "bezier", points = { { 0, 0 }, { 1, 1 } } })

-- shared defaults keep leaf overrides small without hiding native animation fields
local function animation(leaf, overrides)
	local options = {
		leaf = leaf,
		enabled = true,
		speed = 4,
		bezier = "easeOutQuint",
	}

	for key, value in pairs(overrides or {}) do
		options[key] = value
	end

	hl.animation(options)
end

animation("global")
animation("windows", { style = "popin 87%" })
animation("windowsIn", { style = "popin 87%" })
animation("windowsOut", { speed = 2, style = "popin 87%" })
animation("fadeIn", { speed = 2 })
animation("fadeOut", { speed = 2 })
animation("workspaces", { style = "slide" })
animation("layers", { speed = 3, style = "fade" })
