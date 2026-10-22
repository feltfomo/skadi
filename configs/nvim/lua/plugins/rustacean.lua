return {
	"mrcjkb/rustaceanvim",
	-- v8 targets neovim 0.11 while keeping the rust-specific lsp extensions stable
	version = "^8",
	lazy = false,
	dependencies = { "mfussenegger/nvim-dap" },
	init = function()
		vim.g.rustaceanvim = {
			tools = {
				float_win_config = { border = "rounded" },
			},
			server = {
				default_settings = {
					["rust-analyzer"] = {
						cargo = { allTargets = true },
						check = {
							command = "clippy",
							extraArgs = { "--all-targets" },
						},
						procMacro = { enable = true },
					},
				},
			},
		}
	end,
	config = function()
		vim.api.nvim_create_autocmd("FileType", {
			pattern = "rust",
			callback = function(args)
				local opts = { buffer = args.buf, silent = true }
				vim.keymap.set("n", "<leader>ca", function()
					vim.cmd.RustLsp("codeAction")
				end, vim.tbl_extend("force", opts, { desc = "Rust Code Action" }))
				vim.keymap.set("n", "K", function()
					vim.cmd.RustLsp({ "hover", "actions" })
				end, vim.tbl_extend("force", opts, { desc = "Rust Hover Actions" }))
				vim.keymap.set("n", "<leader>rr", function()
					vim.cmd.RustLsp("runnables")
				end, vim.tbl_extend("force", opts, { desc = "Rust Runnables" }))
				vim.keymap.set("n", "<leader>rt", function()
					vim.cmd.RustLsp("testables")
				end, vim.tbl_extend("force", opts, { desc = "Rust Testables" }))
				vim.keymap.set("n", "<leader>rd", function()
					vim.cmd.RustLsp("debuggables")
				end, vim.tbl_extend("force", opts, { desc = "Rust Debuggables" }))
				vim.keymap.set("n", "<leader>re", function()
					vim.cmd.RustLsp("expandMacro")
				end, vim.tbl_extend("force", opts, { desc = "Expand Rust Macro" }))
			end,
		})
	end,
}
