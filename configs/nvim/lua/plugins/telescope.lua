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
				layout_config = { width = 0.9, height = 0.85 },
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

		local palette_path = vim.fn.stdpath("config") .. "/lua/reactive/palette.lua"

		local function set_hl(name, opts)
			vim.api.nvim_set_hl(0, name, opts)
		end

		local function theme()
			if vim.g.colors_name ~= "reactive" then
				return
			end

			local ok, p = pcall(dofile, palette_path)
			if not ok then
				return
			end

			-- window backgrounds
			set_hl("TelescopeNormal", { bg = p.surface, fg = p.fg })
			set_hl("TelescopePromptNormal", { bg = p.surface, fg = p.fg })
			set_hl("TelescopeResultsNormal", { bg = p.surface, fg = p.fg })
			set_hl("TelescopePreviewNormal", { bg = p.surface, fg = p.fg })

			-- borders
			set_hl("TelescopeBorder", { bg = p.surface, fg = p.outline_variant })
			set_hl("TelescopePromptBorder", { bg = p.surface, fg = p.outline_variant })
			set_hl("TelescopeResultsBorder", { bg = p.surface, fg = p.outline_variant })
			set_hl("TelescopePreviewBorder", { bg = p.surface, fg = p.outline_variant })

			-- titles
			set_hl("TelescopeTitle", { fg = p.primary, bold = true })
			set_hl("TelescopePromptTitle", { fg = p.on_primary_container, bg = p.primary_container, bold = true })
			set_hl("TelescopeResultsTitle", { fg = p.primary, bold = true })
			set_hl("TelescopePreviewTitle", { fg = p.on_tertiary_container, bg = p.tertiary_container, bold = true })

			-- prompt-specific
			set_hl("TelescopePromptPrefix", { fg = p.primary })
			set_hl("TelescopePromptCounter", { fg = p.fg_muted })

			-- selection
			set_hl("TelescopeSelection", { bg = p.container_high, fg = p.fg, bold = true })
			set_hl("TelescopeSelectionCaret", { fg = p.primary, bold = true })
			set_hl("TelescopeMultiSelection", { fg = p.secondary, bold = true })
			set_hl("TelescopeMultiIcon", { fg = p.secondary })

			-- matching
			set_hl("TelescopeMatching", { fg = p.tertiary, bold = true })

			-- preview pane (file listing metadata)
			set_hl("TelescopePreviewLine", { bg = p.container_high })
			set_hl("TelescopePreviewMatch", { fg = p.tertiary, bold = true })
			set_hl("TelescopePreviewDirectory", { fg = p.primary })
			set_hl("TelescopePreviewLink", { fg = p.tertiary })
			set_hl("TelescopePreviewRead", { fg = p.green })
			set_hl("TelescopePreviewWrite", { fg = p.yellow })
			set_hl("TelescopePreviewExecute", { fg = p.error })
			set_hl("TelescopePreviewHyphen", { fg = p.fg_muted })
			set_hl("TelescopePreviewSize", { fg = p.fg_muted })
			set_hl("TelescopePreviewUser", { fg = p.fg_muted })
			set_hl("TelescopePreviewGroup", { fg = p.fg_muted })
			set_hl("TelescopePreviewDate", { fg = p.fg_muted })
			set_hl("TelescopePreviewMessage", { fg = p.fg_muted, italic = true })

			-- results pane (symbol-kind coloring)
			set_hl("TelescopeResultsLineNr", { fg = p.outline })
			set_hl("TelescopeResultsComment", { fg = p.fg_muted, italic = true })
			set_hl("TelescopeResultsIdentifier", { fg = p.fg })
			set_hl("TelescopeResultsFunction", { fg = p.primary })
			set_hl("TelescopeResultsMethod", { fg = p.primary })
			set_hl("TelescopeResultsClass", { fg = p.tertiary })
			set_hl("TelescopeResultsStruct", { fg = p.tertiary })
			set_hl("TelescopeResultsConstant", { fg = p.secondary })
			set_hl("TelescopeResultsNumber", { fg = p.secondary })
			set_hl("TelescopeResultsVariable", { fg = p.fg })
			set_hl("TelescopeResultsFileIcon", { fg = p.fg_muted })

			-- git status pickers
			set_hl("TelescopeResultsDiffAdd", { fg = p.green })
			set_hl("TelescopeResultsDiffChange", { fg = p.yellow })
			set_hl("TelescopeResultsDiffDelete", { fg = p.error })
			set_hl("TelescopeResultsDiffUntracked", { fg = p.fg_muted })
		end

		theme()
		vim.api.nvim_create_autocmd("ColorScheme", {
			group = vim.api.nvim_create_augroup("reactive_telescope", { clear = true }),
			pattern = "reactive",
			callback = theme,
		})
	end,
}
