return {
	"nvim-telescope/telescope.nvim",
	dependencies = { "nvim-lua/plenary.nvim" },
	cmd = "Telescope",
	keys = {
		{
			"<leader><leader>",
			function()
				require("telescope.builtin").find_files({ cwd = require("config.project").root() })
			end,
			desc = "Find Repository Files",
		},
		{
			"<leader>ff",
			function()
				require("telescope.builtin").find_files({ cwd = require("config.project").root() })
			end,
			desc = "Find Repository Files",
		},
		{
			"<leader>fg",
			function()
				require("telescope.builtin").live_grep({ cwd = require("config.project").root() })
			end,
			desc = "Grep Repository",
		},
		{
			"<leader>fF",
			function()
				require("telescope.builtin").find_files({ cwd = require("config.project").module_root() })
			end,
			desc = "Find Current Module Files",
		},
		{
			"<leader>fG",
			function()
				require("telescope.builtin").live_grep({ cwd = require("config.project").module_root() })
			end,
			desc = "Grep Current Module",
		},
		{
			"<leader>pm",
			function()
				require("config.project").pick_module("browse")
			end,
			desc = "Browse Module",
		},
		{
			"<leader>pf",
			function()
				require("config.project").pick_module("find_files")
			end,
			desc = "Find Files in Module",
		},
		{
			"<leader>pg",
			function()
				require("config.project").pick_module("live_grep")
			end,
			desc = "Grep Module",
		},
		{
			"<leader>pa",
			function()
				require("telescope.builtin").find_files({
					cwd = require("config.project").root(),
					find_command = { "rg", "--files", "--glob", "*.md" },
					prompt_title = "Architecture and Contracts",
				})
			end,
			desc = "Project Documentation",
		},
		{ "<leader>fs", "<cmd>Telescope lsp_document_symbols<cr>", desc = "File Symbols" },
		{ "<leader>fS", "<cmd>Telescope lsp_dynamic_workspace_symbols<cr>", desc = "Workspace Symbols" },
		{ "<leader>fr", "<cmd>Telescope resume<cr>", desc = "Resume Search" },
		{ "<leader>fb", "<cmd>Telescope buffers<cr>", desc = "Buffers" },
		{ "<leader>fh", "<cmd>Telescope help_tags<cr>", desc = "Help tags" },
	},
	config = function()
		require("telescope").setup({
			defaults = {
				path_display = { "smart" },
				layout_strategy = "flex",
				layout_config = {
					width = 0.9,
					height = 0.85,
					horizontal = { prompt_position = "top", preview_width = 0.55 },
					vertical = { prompt_position = "top" },
				},
				sorting_strategy = "ascending",
				prompt_prefix = "  ",
				selection_caret = "▍ ",
				entry_prefix = "  ",
				multi_icon = "● ",
				borderchars = { "─", "│", "─", "│", "┌", "┐", "┘", "└" },
				vimgrep_arguments = {
					"rg",
					"--color=never",
					"--no-heading",
					"--with-filename",
					"--line-number",
					"--column",
					"--smart-case",
					"--hidden",
					"--glob",
					"!.git/*",
				},
			},
			pickers = {
				find_files = { hidden = true, find_command = { "rg", "--files", "--hidden", "--glob", "!.git/*" } },
				buffers = { sort_mru = true, ignore_current_buffer = true },
			},
		})
	end,
}
