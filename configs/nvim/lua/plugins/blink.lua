return {
	"saghen/blink.cmp",
	dependencies = { "rafamadriz/friendly-snippets" },
	-- pinned to a release so the rust fuzzy matcher ships prebuilt, no local cargo build needed
	version = "1.*",
	---@module 'blink.cmp'
	---@type blink.cmp.Config
	event = "InsertEnter",
	opts = {
		keymap = { preset = "default" },
		appearance = {
			nerd_font_variant = "mono",
		},
		completion = {
			ghost_text = { enabled = true },
			menu = {
				border = "rounded",
			},
			documentation = {
				window = {
					border = "rounded",
				},
			},
		},
		signature = {
			window = {
				border = "rounded",
			},
		},
		sources = {
			default = { "lsp", "path", "snippets", "buffer" },
		},
	},
}
