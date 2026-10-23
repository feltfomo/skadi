return {
	"stevearc/quicker.nvim",
	ft = "qf",
	opts = {
		keys = {
			{
				">",
				function()
					require("quicker").expand({ before = 2, after = 2, add_to_existing = true })
				end,
				desc = "Expand Context",
			},
			{
				"<",
				function()
					require("quicker").collapse()
				end,
				desc = "Collapse Context",
			},
		},
	},
	keys = {
		{
			"<leader>xq",
			function()
				require("quicker").toggle()
			end,
			desc = "Toggle Quickfix",
		},
		{
			"<leader>xl",
			function()
				require("quicker").toggle({ loclist = true })
			end,
			desc = "Toggle Location List",
		},
	},
}
