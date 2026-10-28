return {
	"mfussenegger/nvim-lint",
	ft = "nix",
	config = function()
		local lint = require("lint")
		lint.linters_by_ft = { nix = { "statix", "deadnix" } }
		vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost" }, {
			group = vim.api.nvim_create_augroup("editor_lint", { clear = true }),
			callback = function(args)
				if vim.bo[args.buf].buftype == "" and vim.bo[args.buf].filetype == "nix" then
					vim.api.nvim_buf_call(args.buf, function()
						lint.try_lint(nil, {
							filter = function(linter)
								return vim.fn.executable(linter.cmd) == 1
							end,
						})
					end)
				end
			end,
		})
	end,
}
