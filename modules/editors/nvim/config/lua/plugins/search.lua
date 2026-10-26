return {
	"MagicDuck/grug-far.nvim",
	cmd = { "GrugFar", "GrugFarWithin" },
	opts = {},
	keys = {
		{
			"<leader>sr",
			function()
				require("grug-far").open({ prefills = { paths = require("config.project").root():gsub(" ", "\\ ") } })
			end,
			desc = "Search and Replace Repository",
		},
		{
			"<leader>sw",
			function()
				require("grug-far").open({
					prefills = {
						paths = require("config.project").root():gsub(" ", "\\ "),
						search = vim.fn.expand("<cword>"),
					},
				})
			end,
			desc = "Search and Replace Word",
		},
	},
}
