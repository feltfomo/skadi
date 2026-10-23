return {
	{
		"nvim-mini/mini.surround",
		branch = "stable",
		event = "VeryLazy",
		opts = {
			mappings = {
				add = "gsa",
				delete = "gsd",
				replace = "gsr",
				find = "gsf",
				find_left = "gsF",
				highlight = "gsh",
			},
		},
	},
	{
		"folke/flash.nvim",
		opts = { modes = { char = { enabled = false } } },
		keys = {
			{
				"s",
				function()
					require("flash").jump()
				end,
				mode = { "n", "x", "o" },
				desc = "Flash Jump",
			},
			{
				"S",
				function()
					require("flash").treesitter()
				end,
				mode = { "n", "x", "o" },
				desc = "Flash Syntax Selection",
			},
		},
	},
	{
		"nvim-treesitter/nvim-treesitter-textobjects",
		branch = "main",
		event = "VeryLazy",
		opts = { select = { lookahead = true }, move = { set_jumps = true } },
		config = function(_, opts)
			require("nvim-treesitter-textobjects").setup(opts)
			for lhs, capture in pairs({
				af = "@function.outer",
				["if"] = "@function.inner",
				ac = "@class.outer",
				ic = "@class.inner",
				aa = "@parameter.outer",
				ia = "@parameter.inner",
			}) do
				vim.keymap.set({ "x", "o" }, lhs, function()
					require("nvim-treesitter-textobjects.select").select_textobject(capture, "textobjects")
				end, { desc = "Select " .. capture })
			end
			for lhs, motion in pairs({
				["]f"] = { "goto_next_start", "@function.outer" },
				["[f"] = { "goto_previous_start", "@function.outer" },
				["]C"] = { "goto_next_start", "@class.outer" },
				["[C"] = { "goto_previous_start", "@class.outer" },
			}) do
				vim.keymap.set({ "n", "x", "o" }, lhs, function()
					require("nvim-treesitter-textobjects.move")[motion[1]](motion[2], "textobjects")
				end, { desc = "Move to " .. motion[2] })
			end
			vim.keymap.set("n", "<leader>c>", function()
				require("nvim-treesitter-textobjects.swap").swap_next("@parameter.inner")
			end, { desc = "Swap Argument Forward" })
			vim.keymap.set("n", "<leader>c<", function()
				require("nvim-treesitter-textobjects.swap").swap_previous("@parameter.inner")
			end, { desc = "Swap Argument Backward" })
		end,
	},
}
