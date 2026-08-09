return {
	"neovim/nvim-lspconfig",
	lazy = false,
	config = function()
		-- vim.lsp.config() merges onto whichever base config resolves for
		-- that name, so these overrides apply regardless of load order
		-- between this repo's lsp/*.lua files and nvim-lspconfig's own.
		vim.lsp.config("lua_ls", {
			root_dir = function(bufnr, on_dir)
				on_dir("/etc/skadi/configs/nvim")
			end,
			settings = {
				Lua = {
					diagnostics = { globals = { "vim" } },
				},
			},
		})
		vim.lsp.config("rust_analyzer", {
			settings = {
				["rust-analyzer"] = {
					check = { command = "clippy" },
				},
			},
		})

		vim.lsp.enable({
			"nixd",
			"lua_ls",
			"rust_analyzer",
			"jdtls",
			"kotlin_language_server",
			"pyright",
			"zls",
			"ols",
		})
	end,
}
