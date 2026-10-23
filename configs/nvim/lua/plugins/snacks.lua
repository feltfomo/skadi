return {
	"folke/snacks.nvim",
	priority = 1000,
	lazy = false,
	---@type snacks.Config
	keys = {
		{
			"]r",
			function()
				Snacks.words.jump(vim.v.count1)
			end,
			desc = "Next Symbol Reference",
		},
		{
			"[r",
			function()
				Snacks.words.jump(-vim.v.count1)
			end,
			desc = "Previous Symbol Reference",
		},
		{
			"<leader>g",
			function()
				Snacks.lazygit()
			end,
			desc = "Lazygit",
		},
	},
	opts = {
		dashboard = {
			width = 100,
			preset = {
				header = [[
                                       __        ____      __
                                      /  \       \   \    /  \
                                      \   \       \   \  /   /
                                       \   \       \   \/   /
                                  ______\   \______ \      /
                                 /                 \ \    /     /\
                                /_______    ________\ \   \    /  \
                                       /   /           \   \  /   /
                                      /   /             \  / /   /
                             ________/   /               \/ /   /_____
                            /           /                  /          \
                            \______    /                  /   ________/
                                  /   / /\               /   /
                                 /   / /  \             /   /
                                /   /  \   \  _________/   /______
                                \  /    \   \ \                  /
                                 \/     /    \ \______    ______/
                                       /      \       \   \
                                      /   /\   \       \   \
                                     /   /  \   \       \   \
                                     \__/    \___\       \__/]],
			},
			formats = {
				header = { "%s", align = "left" },
			},
		},
		explorer = { enabled = false },
		input = {},
		indent = {},
		bigfile = {},
		words = {},
		lazygit = {},
		notifier = {
			style = "fancy",
		},
	},
}
