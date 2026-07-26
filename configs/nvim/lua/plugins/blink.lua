return {
	"saghen/blink.cmp",
	-- pinned to a release so the rust fuzzy matcher ships prebuilt, no local cargo build needed
	version = "1.*",
	event = "InsertEnter",
	opts = {
		keymap = { preset = "default" },
		appearance = {
			nerd_font_variant = "mono",
		},
		completion = {
			ghost_text = { enabled = true },
		},
		sources = {
			default = { "lsp", "path", "snippets", "buffer" },
		},
	},
}
