return {
	"stevearc/oil.nvim",
	---@module 'oil'
	---@type oil.SetupOpts
	opts = {
		float = {
			border = "rounded",
		},
	},
	lazy = false,
	keys = {
		{
			"<leader>-",
			function()
				require("oil").toggle_float()
			end,
			desc = "Toggle oil (float)",
		},
	},
}
