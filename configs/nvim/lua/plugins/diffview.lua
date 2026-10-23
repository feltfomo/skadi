return {
	"sindrets/diffview.nvim",
	cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewFileHistory" },
	keys = {
		{ "<leader>hv", "<cmd>DiffviewOpen<cr>", desc = "Review Repository Diff" },
		{ "<leader>hH", "<cmd>DiffviewFileHistory %<cr>", desc = "File History" },
		{ "<leader>hc", "<cmd>DiffviewClose<cr>", desc = "Close Diff Review" },
	},
	opts = {},
}
