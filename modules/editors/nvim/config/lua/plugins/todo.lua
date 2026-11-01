return {
	"folke/todo-comments.nvim",
	dependencies = { "nvim-lua/plenary.nvim" },
	event = { "BufReadPost", "BufNewFile" },
	opts = { signs = false },
	keys = {
		{ "<leader>ft", "<cmd>TodoTelescope<cr>", desc = "Find TODOs" },
	},
}
