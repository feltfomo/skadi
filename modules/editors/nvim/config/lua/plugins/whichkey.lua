return {
	"folke/which-key.nvim",
	event = "VeryLazy",
	opts = {
		preset = "helix",
		spec = {
			{ "<leader>b", group = "Buffers" },
			{ "<leader>c", group = "Code" },
			{ "<leader>d", group = "Debug" },
			{ "<leader>f", group = "Find" },
			{ "<leader>h", group = "Git Hunks" },
			{ "<leader>k", group = "Kotlin" },
			{ "<leader>m", group = "Markdown" },
			{ "<leader>n", group = "Messages" },
			{ "<leader>p", group = "Project" },
			{ "<leader>q", group = "Sessions" },
			{ "<leader>r", group = "Rust" },
			{ "<leader>s", group = "Search and Replace" },
			{ "<leader>t", group = "Tasks" },
			{ "<leader>u", group = "View" },
			{ "<leader>x", group = "Diagnostics" },
		},
	},
	keys = {
		{
			"<leader>?",
			function()
				require("which-key").show({ global = false })
			end,
			desc = "Buffer Local Keymaps (which-key)",
		},
	},
}
