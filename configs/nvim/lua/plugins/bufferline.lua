return {
	"akinsho/bufferline.nvim",
	version = "*",
	event = "VeryLazy",
	dependencies = { "echasnovski/mini.icons" },
	opts = {
		options = {
			diagnostics = "nvim_lsp",
			separator_style = "slant",
			always_show_bufferline = true,
			offsets = {
				{
					filetype = "oil",
					text = "Files",
					highlight = "Directory",
					separator = true,
				},
			},
		},
	},
	keys = {
		{ "<S-h>", "<cmd>BufferLineCyclePrev<cr>", desc = "Previous Buffer" },
		{ "<S-l>", "<cmd>BufferLineCycleNext<cr>", desc = "Next Buffer" },
		{ "<leader>bp", "<cmd>BufferLineTogglePin<cr>", desc = "Pin Buffer" },
		{ "<leader>bo", "<cmd>BufferLineCloseOthers<cr>", desc = "Close Other Buffers" },
		{ "<leader>bd", "<cmd>bdelete<cr>", desc = "Delete Buffer" },
	},
}
