return {
	"AlexandrosAlexiou/kotlin.nvim",
	cond = function()
		return vim.env.KOTLIN_LSP_DIR ~= nil
	end,
	ft = "kotlin",
	dependencies = { "stevearc/oil.nvim", "folke/trouble.nvim", "mfussenegger/nvim-dap" },
	opts = {
		root_markers = {
			{ "settings.gradle.kts", "settings.gradle", ".git" },
			{ "build.gradle.kts", "build.gradle", "pom.xml" },
		},
		jdk_for_symbol_resolution = vim.env.JAVA_HOME,
		inlay_hints = {
			enabled = false,
			parameters_compiled = false,
			types_variable = false,
			lambda_return = false,
			lambda_receivers_parameters = false,
			value_ranges = false,
			kotlin_time = false,
		},
		file_templates = { enabled = false },
		reload_workspace = { on_build_file_save = "ask" },
		dap = { configurations = false },
	},
	keys = {
		{ "<leader>ko", "<cmd>KotlinOrganizeImports<cr>", desc = "Organize Kotlin Imports" },
		{ "<leader>kr", "<cmd>KotlinReloadWorkspace<cr>", desc = "Reload Kotlin Build" },
		{ "<leader>kd", "<cmd>KotlinDebug<cr>", desc = "Debug Kotlin" },
	},
}
