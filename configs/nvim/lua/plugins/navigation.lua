return {
	{
		"nvim-neo-tree/neo-tree.nvim",
		branch = "v3.x",
		lazy = false,
		cmd = "Neotree",
		dependencies = { "nvim-lua/plenary.nvim", "MunifTanjim/nui.nvim", "echasnovski/mini.icons" },
		keys = {
			{ "<leader>e", "<cmd>Neotree toggle<cr>", desc = "Toggle File Tree" },
			{
				"<leader>E",
				function()
					require("config.project").browse(require("config.project").root(), vim.api.nvim_buf_get_name(0))
				end,
				desc = "Reveal File in Repository",
			},
			{
				"<leader>pe",
				function()
					require("config.project").browse(require("config.project").root())
				end,
				desc = "Repository Tree",
			},
		},
		opts = {
			close_if_last_window = true,
			popup_border_style = "rounded",
			source_selector = { winbar = true, statusline = false },
			window = { width = 42 },
			filesystem = {
				bind_to_cwd = false,
				group_empty_dirs = true,
				follow_current_file = { enabled = true, leave_dirs_open = true },
				filtered_items = {
					hide_dotfiles = false,
					hide_gitignored = true,
					never_show = { ".git" },
				},
			},
		},
	},
	{
		"Bekaboo/dropbar.nvim",
		event = { "BufReadPost", "BufNewFile" },
		keys = {
			{
				"<leader>cb",
				function()
					require("dropbar.api").pick()
				end,
				desc = "Pick Breadcrumb",
			},
		},
		opts = {
			sources = {
				path = {
					relative_to = function(buf)
						return require("config.project").root(buf)
					end,
				},
			},
		},
	},
	{
		"nvim-treesitter/nvim-treesitter-context",
		event = { "BufReadPost", "BufNewFile" },
		opts = { max_lines = 3, multiline_threshold = 1, min_window_height = 20 },
		keys = {
			{ "<leader>ut", "<cmd>TSContext toggle<cr>", desc = "Toggle Sticky Context" },
		},
	},
}
