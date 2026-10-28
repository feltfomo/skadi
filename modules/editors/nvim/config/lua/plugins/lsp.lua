return {
	"neovim/nvim-lspconfig",
	lazy = false,
	dependencies = { "mfussenegger/nvim-jdtls", "mfussenegger/nvim-dap", "b0o/SchemaStore.nvim" },
	config = function()
		vim.lsp.config("nixd", {
			settings = { nixd = {} },
			before_init = function(_, config)
				config.settings.nixd = require("config.nix").settings(config.root_dir)
			end,
		})
		vim.lsp.config("jsonls", {
			settings = { json = { schemas = require("schemastore").json.schemas(), validate = { enable = true } } },
		})
		vim.lsp.config("yamlls", {
			settings = {
				yaml = {
					schemaStore = { enable = false, url = "" },
					schemas = require("schemastore").yaml.schemas(),
				},
			},
		})
		vim.lsp.config("lua_ls", {
			settings = {
				Lua = {
					diagnostics = { globals = { "vim" } },
				},
			},
		})
		local debug_dir = vim.env.NVIM_JAVA_DEBUG_DIR
		vim.lsp.config("jdtls", {
			init_options = {
				extendedClientCapabilities = require("jdtls").extendedClientCapabilities,
				bundles = debug_dir and vim.fn.glob(debug_dir .. "/com.microsoft.java.debug.plugin-*.jar", false, true)
					or {},
			},
			settings = {
				java = {
					signatureHelp = { enabled = true },
					inlayHints = { parameterNames = { enabled = "literals" } },
					format = { enabled = false },
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
			group = vim.api.nvim_create_augroup("editor_lsp", { clear = true }),
			callback = function(args)
				local client = vim.lsp.get_client_by_id(args.data.client_id)
				if not client then
					return
				end
				if client.name == "ruff" then
					client.server_capabilities.hoverProvider = false
				end

				local opts = { buffer = args.buf, silent = true }
				local function map(lhs, rhs, desc)
					vim.keymap.set("n", lhs, rhs, vim.tbl_extend("force", opts, { desc = desc }))
				end
				map("gd", vim.lsp.buf.definition, "Go to Definition")
				map("gD", vim.lsp.buf.declaration, "Go to Declaration")
				map("gr", function()
					require("telescope.builtin").lsp_references()
				end, "Find References")
				map("gI", function()
					require("telescope.builtin").lsp_implementations()
				end, "Find Implementations")
				map("gy", vim.lsp.buf.type_definition, "Go to Type Definition")
				map("<leader>cr", vim.lsp.buf.rename, "Rename Symbol")
				if client.name ~= "rust-analyzer" then
					map("<leader>ca", vim.lsp.buf.code_action, "Code Action")
				end
				map("<leader>uh", function()
					vim.lsp.inlay_hint.enable(
						not vim.lsp.inlay_hint.is_enabled({ bufnr = args.buf }),
						{ bufnr = args.buf }
					)
				end, "Toggle Inlay Hints")
				map("<leader>ud", function()
					vim.diagnostic.enable(not vim.diagnostic.is_enabled({ bufnr = args.buf }), { bufnr = args.buf })
				end, "Toggle Buffer Diagnostics")
				if client:supports_method("textDocument/foldingRange") then
					vim.wo.foldexpr = "v:lua.vim.lsp.foldexpr()"
				end
				if client.name ~= "jdtls" then
					return
				end
				require("jdtls").setup_dap({ hotcodereplace = "auto" })
				map("<leader>dm", function()
					require("jdtls.dap").setup_dap_main_class_configs({ verbose = true })
				end, "Discover Java Main Classes")
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
			virtual_text = false,
			virtual_lines = { current_line = true },
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
			float = { border = "rounded", source = true },
		})

		local servers = {
			jsonls = "vscode-json-language-server",
			yamlls = "yaml-language-server",
			lua_ls = "lua-language-server",
			pyright = "pyright-langserver",
			clangd = "clangd",
			jdtls = "jdtls",
			nixd = "nixd",
			ruff = "ruff",
			ols = "ols",
			zls = "zls",
			nushell = "nu",
		}
		for server, command in pairs(servers) do
			if vim.fn.executable(command) == 1 then
				vim.lsp.enable(server)
			end
		end
	end,
}
