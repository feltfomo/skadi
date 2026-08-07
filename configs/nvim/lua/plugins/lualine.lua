return {
	"nvim-lualine/lualine.nvim",
	event = "VeryLazy",
	config = function()
		local lualine = require("lualine")
		local palette_path = vim.fn.stdpath("config") .. "/lua/reactive/palette.lua"

		local function setup()
			if vim.g.colors_name ~= "reactive" then
				lualine.setup()
				return
			end

			local ok, p = pcall(dofile, palette_path)
			if not ok then
				lualine.setup()
				return
			end

			local function mode(bg, fg)
				return {
					a = { bg = bg, fg = fg, gui = "bold" },
					b = { bg = p.container, fg = p.fg },
					c = { bg = p.surface, fg = p.fg },
				}
			end

			lualine.setup({
				options = {
					theme = {
						normal = mode(p.primary, p.on_primary),
						insert = mode(p.secondary_container, p.on_secondary_container),
						visual = mode(p.tertiary, p.on_tertiary),
						replace = mode(p.error_container, p.on_error_container),
						command = mode(p.primary_container, p.on_primary_container),
						inactive = {
							a = { bg = p.bg_dim, fg = p.fg_muted },
							b = { bg = p.bg_dim, fg = p.fg_muted },
							c = { bg = p.bg_dim, fg = p.fg_muted },
						},
					},
				},
			})
		end

		setup()
		vim.api.nvim_create_autocmd("ColorScheme", {
			group = vim.api.nvim_create_augroup("reactive_lualine", { clear = true }),
			pattern = "reactive",
			callback = setup,
		})
	end,
}
