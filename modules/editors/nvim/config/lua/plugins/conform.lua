return {
	"stevearc/conform.nvim",
	event = { "BufWritePre" },
	cmd = { "ConformInfo" },
	keys = {
		{
			"<leader>cf",
			function()
				require("conform").format({ async = true, lsp_format = "never" })
			end,
			desc = "Format File or Selection",
			mode = { "n", "x" },
		},
	},
	opts = {
		formatters_by_ft = {
			nix = { "nixfmt" },
			lua = { "stylua" },
			java = { "google_java_format" },
			kotlin = { "ktlint" },
			rust = { "rustfmt" },
			python = { "ruff_format" },
			c = { "clang_format" },
			toml = { "taplo" },
			markdown = { "prettier" },
			yaml = { "prettier" },
		},
		format_on_save = function(buf)
			-- Java formatting is manual in Odyssey; save must not rewrite those files.
			if vim.bo[buf].filetype == "java" then
				return
			end
			if #require("conform").list_formatters(buf) == 0 then
				return
			end
			return { timeout_ms = 2000, lsp_format = "never" }
		end,
	},
}
