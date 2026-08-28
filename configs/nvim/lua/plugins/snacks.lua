return {
	"folke/snacks.nvim",
	priority = 1000,
	lazy = false,
	---@type snacks.Config
	keys = {
		{
			"<leader>e",
			function()
				Snacks.explorer()
			end,
			desc = "File Explorer",
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
		explorer = {},
		indent = {},
		lazygit = {},
		notifier = {
			style = "fancy",
		},
	},
}
