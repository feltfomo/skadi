return {
	"neovim/nvim-lspconfig",
	lazy = false,
	dependencies = { "mfussenegger/nvim-jdtls" },
	config = function()
		-- vim.lsp.config() merges onto whichever base config resolves for
		-- that name, so these overrides apply regardless of load order
		-- between this repo's lsp/*.lua files and nvim-lspconfig's own.
		vim.lsp.config("lua_ls", {
			root_dir = function(_, on_dir)
				on_dir("/etc/skadi/configs/nvim")
			end,
			settings = {
				Lua = {
					diagnostics = { globals = { "vim" } },
				},
			},
		})
		vim.lsp.config("jdtls", {
			settings = {
				java = {
					configuration = { updateBuildConfiguration = "interactive" },
					import = {
						gradle = {
							enabled = true,
							wrapper = { enabled = true },
						},
					},
				},
			},
		})

		-- rustaceanvim owns rust-analyzer so only one client attaches per buffer
		vim.api.nvim_create_autocmd("LspAttach", {
			callback = function(args)
				local client = vim.lsp.get_client_by_id(args.data.client_id)
				if not client or client.name ~= "jdtls" then
					return
				end

				local opts = { buffer = args.buf, silent = true }
				vim.keymap.set("n", "<leader>co", function()
					require("jdtls").organize_imports()
				end, vim.tbl_extend("force", opts, { desc = "Organize Java Imports" }))
				vim.keymap.set("n", "<leader>cv", function()
					require("jdtls").extract_variable()
				end, vim.tbl_extend("force", opts, { desc = "Extract Java Variable" }))
				vim.keymap.set("v", "<leader>cv", function()
					require("jdtls").extract_variable(true)
				end, vim.tbl_extend("force", opts, { desc = "Extract Java Variable" }))
			end,
		})

		vim.diagnostic.config({
			virtual_text = {
				spacing = 4,
				prefix = function(diagnostic)
					local icons = {
						[vim.diagnostic.severity.ERROR] = " ",
						[vim.diagnostic.severity.WARN] = " ",
						[vim.diagnostic.severity.INFO] = " ",
						[vim.diagnostic.severity.HINT] = " ",
					}
					return icons[diagnostic.severity] or "●"
				end,
			},
			signs = {
				text = {
					[vim.diagnostic.severity.ERROR] = " ",
					[vim.diagnostic.severity.WARN] = " ",
					[vim.diagnostic.severity.INFO] = " ",
					[vim.diagnostic.severity.HINT] = " ",
				},
			},
			underline = true,
			severity_sort = true,
		})

		vim.lsp.enable({
			"nixd",
			"lua_ls",
			"jdtls",
			"kotlin_language_server",
			"pyright",
			"zls",
			"ols",
		})
	end,
}
