return {
	"stevearc/oil.nvim",
	---@module 'oil'
	---@type oil.SetupOpts
	opts = {
		default_file_explorer = false,
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
