hl.config({
	general = {
		gaps_in = 5,
		gaps_out = 15,
		border_size = 0,
		layout = "dwindle",
	},

	decoration = {
		rounding = 10,
		rounding_power = 4,
		active_opacity = 0.95,
		inactive_opacity = 0.82,
		blur = {
			enabled = true,
			size = 10,
			passes = 3,
			new_optimizations = true,
		},
		shadow = {
			enabled = true,
			range = 16,
			render_power = 4,
		},
	},

	animations = {
		enabled = true,
	},
})

-- animation curves (bezier control points): new Lua API takes a table
-- hl.curve(NAME, { type = "bezier", points = { {x0, y0}, {x1, y1} } })
hl.curve("easeOutQuint", { type = "bezier", points = { { 0.23, 1 }, { 0.32, 1 } } })
hl.curve("easeInOutCubic", { type = "bezier", points = { { 0.65, 0.05 }, { 0.36, 1 } } })
hl.curve("linear", { type = "bezier", points = { { 0, 0 }, { 1, 1 } } })

-- animations: new Lua API takes a single table per leaf
-- "global" is the parent leaf every animation inherits from
hl.animation({ leaf = "global", enabled = true, speed = 4, bezier = "easeOutQuint" })
hl.animation({ leaf = "windows", enabled = true, speed = 4, bezier = "easeOutQuint", style = "popin 87%" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 4, bezier = "easeOutQuint", style = "popin 87%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 2, bezier = "easeOutQuint", style = "popin 87%" })
hl.animation({ leaf = "fadeIn", enabled = true, speed = 2, bezier = "easeOutQuint" })
hl.animation({ leaf = "fadeOut", enabled = true, speed = 2, bezier = "easeOutQuint" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 4, bezier = "easeOutQuint", style = "slide" })
hl.animation({ leaf = "layers", enabled = true, speed = 3, bezier = "easeOutQuint", style = "fade" })
