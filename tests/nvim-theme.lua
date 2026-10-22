local repo = assert(arg[1], "pass the repository root")
vim.opt.runtimepath:prepend(repo .. "/configs/nvim")
vim.opt.runtimepath:prepend(assert(arg[2], "pass the mini.hues plugin directory"))

local function luminance(color)
	local rgb = {}
	for channel in color:gmatch("%x%x") do
		local value = tonumber(channel, 16) / 255
		rgb[#rgb + 1] = value <= 0.04045 and value / 12.92 or ((value + 0.055) / 1.055) ^ 2.4
	end
	return 0.2126 * rgb[1] + 0.7152 * rgb[2] + 0.0722 * rgb[3]
end

local function contrast(a, b)
	local x, y = luminance(a), luminance(b)
	return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05)
end

local function color(group)
	local value = vim.api.nvim_get_hl(0, { name = group, link = false }).fg
	assert(value, "missing foreground: " .. group)
	return string.format("#%06x", value)
end

local directory = vim.fn.stdpath("config") .. "/lua/reactive"
vim.fn.mkdir(directory, "p")
for _, base in ipairs({
	{ bg = "#131315", fg = "#e5e2e3", accent = "#c3c6d6" },
	{ bg = "#fcf8fa", fg = "#1b1b1d", accent = "#5a5e6c" },
	{ bg = "#000000", fg = "#ffffff", accent = "#aaaaaa" },
	{ bg = "#ffffff", fg = "#000000", accent = "#555555" },
	{ bg = "#11262d", fg = "#c0c8cc", accent = "#88c0d0" },
	{ bg = "#281a1a", fg = "#f0dada", accent = "#ddaaaa" },
}) do
	local palette = { bg = base.bg, fg = base.fg, term = {} }
	for _, name in ipairs({ "bg_dim", "surface", "container", "container_high", "container_highest" }) do
		palette[name] = base.bg
	end
	for _, name in ipairs({
		"on_secondary_container",
		"on_tertiary_container",
		"on_primary_container",
		"on_error_container",
		"secondary_container",
		"tertiary_container",
		"primary_container",
		"error_container",
		"outline_variant",
		"on_tertiary",
		"on_primary",
		"fg_muted",
		"secondary",
		"tertiary",
		"primary",
		"outline",
		"yellow",
		"green",
		"error",
	}) do
		palette[name] = base.accent
	end
	vim.fn.writefile(vim.split("return " .. vim.inspect(palette), "\n", { plain = true }), directory .. "/palette.lua")
	vim.cmd.colorscheme("reactive")
	local normal = vim.api.nvim_get_hl(0, { name = "Normal" })
	assert(normal.bg == tonumber(base.bg:sub(2), 16), "wallpaper background changed")
	assert(color("Directory") == base.accent, "wallpaper accent changed")
	local colors = {}
	for _, group in ipairs({ "Function", "String", "Keyword", "Type", "Number" }) do
		local foreground = color(group)
		assert(contrast(foreground, base.bg) >= 4.5, group .. " has insufficient contrast on " .. base.bg)
		local channels = {}
		for value in foreground:gmatch("%x%x") do
			channels[#channels + 1] = tonumber(value, 16)
		end
		assert(math.max(unpack(channels)) - math.min(unpack(channels)) >= 40, group .. " lost its hue")
		for _, other in ipairs(colors) do
			local distance = 0
			for i, value in ipairs(channels) do
				distance = distance + (value - other[i]) ^ 2
			end
			assert(distance >= 25 ^ 2, "syntax roles converged on " .. base.bg)
		end
		colors[#colors + 1] = channels
	end
	assert(contrast(color("Comment"), base.bg) >= 4.5, "comments became unreadable")
	assert(color("@lsp.type.method") == color("Function"), "semantic method overrides the syntax role")
	assert(color("@lsp.type.class") == color("Type"), "semantic class overrides the syntax role")
	assert(color("@lsp.type.property") == color("@property"), "semantic property overrides the syntax role")
	assert(color("RenderMarkdownH1") ~= color("RenderMarkdownH2"), "Markdown headings converged")
end
print("syntax theme passed: contrast, distinct roles, semantic tokens, wallpaper colors, and repeated palette reloads")
