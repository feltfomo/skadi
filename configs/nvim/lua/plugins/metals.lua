return {
	"scalameta/nvim-metals",
	ft = { "scala", "sbt" },
	dependencies = { "nvim-lua/plenary.nvim" },
	config = function()
		local metals_config = require("metals").bare_config()
		vim.api.nvim_create_autocmd("FileType", {
			pattern = { "scala", "sbt" },
			callback = function()
				require("metals").initialize_or_attach(metals_config)
			end,
		})
	end,
}
