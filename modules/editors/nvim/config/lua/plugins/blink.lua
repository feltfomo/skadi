return {
	"saghen/blink.cmp",
	dependencies = { "rafamadriz/friendly-snippets" },
	-- pinned to a release so the rust fuzzy matcher ships prebuilt, no local cargo build needed
	version = "1.*",
	event = "InsertEnter",
	---@module 'blink.cmp'
	---@type blink.cmp.Config
	opts = {
		keymap = { preset = "default" },
		appearance = {
			nerd_font_variant = "mono",
		},
		completion = {
			accept = { auto_brackets = { blocked_filetypes = { "kotlin" } } },
			ghost_text = { enabled = true },
			menu = {
				border = "single",
				draw = {
					columns = { { "kind_icon" }, { "label", "label_description", gap = 1 } },
				},
			},
			documentation = {
				auto_show = true,
				auto_show_delay_ms = 300,
				window = {
					border = "single",
				},
			},
		},
		signature = {
			enabled = true,
			window = {
				border = "single",
			},
		},
		sources = {
			default = { "lsp", "path", "snippets", "buffer" },
		},
	},
}
