return {
	"nvim-treesitter/nvim-treesitter",
	branch = "main",
	build = ":TSUpdate",
	config = function()
		require("nvim-treesitter").install({
			"markdown_inline",
			"markdown",
			"kotlin",
			"luadoc",
			"python",
			"vimdoc",
			"query",
			"bash",
			"diff",
			"java",
			"json",
			"rust",
			"toml",
			"yaml",
			"cpp",
			"lua",
			"nix",
			"nu",
			"vim",
			"c",
		})

		vim.api.nvim_create_autocmd("FileType", {
			pattern = "*",
			callback = function()
				if pcall(vim.treesitter.start) then
					vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
				end
			end,
		})
	end,
}
