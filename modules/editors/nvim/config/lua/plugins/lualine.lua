return {
	"nvim-lualine/lualine.nvim",
	event = "VeryLazy",
	config = function()
		local lualine = require("lualine")
		local palette_path = vim.fn.stdpath("config") .. "/lua/reactive/palette.lua"

		local function theme()
			if vim.g.colors_name ~= "reactive" then
				return "auto"
			end

			local ok, p = pcall(dofile, palette_path)
			if not ok then
				return "auto"
			end

			local quiet = { bg = p.surface, fg = p.fg_muted }
			local function mode(bg, fg)
				return {
					a = { bg = bg, fg = fg, gui = "bold" },
					b = quiet,
					c = { bg = p.surface, fg = p.fg },
					z = quiet,
				}
			end

			return {
				normal = mode(p.primary, p.on_primary),
				insert = mode(p.secondary_container, p.on_secondary_container),
				visual = mode(p.tertiary, p.on_tertiary),
				replace = mode(p.error_container, p.on_error_container),
				command = mode(p.primary_container, p.on_primary_container),
			}
		end

		-- noice hides the native recording message, so nothing else shows a running macro
		local function recording()
			local register = vim.fn.reg_recording()
			return register ~= "" and "rec @" .. register or ""
		end

		local function setup()
			lualine.setup({
				options = {
					theme = theme(),
					globalstatus = true,
					section_separators = "",
					component_separators = "",
				},
				sections = {
					-- the mode's color carries the rest, so one letter is enough
					lualine_a = {
						{
							"mode",
							fmt = function(name)
								return name:sub(1, 1)
							end,
						},
					},
					lualine_b = { "branch" },
					lualine_c = {
						{
							"filename",
							path = 1,
							symbols = { modified = "●", readonly = "", unnamed = "", newfile = "" },
						},
					},
					lualine_x = { recording, "diagnostics", "diff" },
					lualine_y = {},
					lualine_z = { "location" },
				},
			})
		end

		setup()

		local group = vim.api.nvim_create_augroup("reactive_lualine", { clear = true })
		vim.api.nvim_create_autocmd("ColorScheme", { group = group, pattern = "reactive", callback = setup })
		-- lualine's refresh timer would show a macro up to a second late
		vim.api.nvim_create_autocmd({ "RecordingEnter", "RecordingLeave" }, {
			group = group,
			callback = function()
				vim.schedule(lualine.refresh)
			end,
		})
	end,
}
