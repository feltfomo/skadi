local square = { border = { style = "single" } }

return {
	"folke/noice.nvim",
	event = "VeryLazy",
	dependencies = { "MunifTanjim/nui.nvim" },
	opts = {
		lsp = {
			signature = { enabled = false },
			override = {
				["vim.lsp.util.convert_input_to_markdown_lines"] = true,
				["vim.lsp.util.stylize_markdown"] = true,
			},
		},
		-- presets apply after user options, so their rounded borders are overridden in place
		presets = {
			bottom_search = true,
			command_palette = { views = { cmdline_popup = square, cmdline_popupmenu = square } },
			long_message_to_split = true,
			lsp_doc_border = { views = { hover = square } },
		},
		views = { cmdline_input = square, confirm = square, popup = square, popupmenu = square },
	},
	keys = {
		{ "<leader>nl", "<cmd>Noice last<cr>", desc = "Last Message" },
		{ "<leader>nh", "<cmd>Noice history<cr>", desc = "Message History" },
		{ "<leader>ne", "<cmd>Noice errors<cr>", desc = "Message Errors" },
		{ "<leader>nd", "<cmd>Noice dismiss<cr>", desc = "Dismiss Messages" },
	},
}
