return {
	"akinsho/bufferline.nvim",
	version = "*",
	event = "VeryLazy",
	dependencies = { "echasnovski/mini.icons" },
	opts = {
		options = {
			diagnostics = "nvim_lsp",
			themable = true,
			separator_style = { "", "" },
			indicator = { icon = "▍", style = "icon" },
			modified_icon = "●",
			show_buffer_close_icons = false,
			show_close_icon = false,
			tab_size = 16,
			always_show_bufferline = true,
			offsets = {
				{ filetype = "neo-tree", text = "Project", highlight = "Directory", separator = true },
				{
					filetype = "oil",
					text = "Files",
					highlight = "Directory",
					separator = true,
				},
			},
		},
		-- bufferline derives its own shades, so every state is pointed back at the theme's tabline
		highlights = function(defaults)
			if vim.g.colors_name ~= "reactive" then
				return {}
			end
			local function color(group, attribute)
				return string.format("#%06x", vim.api.nvim_get_hl(0, { name = group, link = false })[attribute])
			end
			local selected, inactive = color("TabLineSel", "bg"), color("TabLine", "bg")
			local highlights = {}
			for name, group in pairs(defaults.highlights) do
				if group.bg then
					highlights[name] = { bg = name:find("selected", 1, true) and selected or inactive }
				end
			end
			highlights.fill = { bg = color("TabLineFill", "bg") }
			highlights.indicator_selected = { fg = color("FloatTitle", "fg"), bg = selected }
			return highlights
		end,
	},
	keys = {
		{ "<S-h>", "<cmd>BufferLineCyclePrev<cr>", desc = "Previous Buffer" },
		{ "<S-l>", "<cmd>BufferLineCycleNext<cr>", desc = "Next Buffer" },
		{ "<leader>bp", "<cmd>BufferLineTogglePin<cr>", desc = "Pin Buffer" },
		{ "<leader>bo", "<cmd>BufferLineCloseOthers<cr>", desc = "Close Other Buffers" },
		{ "<leader>bd", "<cmd>bdelete<cr>", desc = "Delete Buffer" },
	},
}
