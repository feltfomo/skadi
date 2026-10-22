return {
	"stevearc/overseer.nvim",
	cmd = { "OverseerTaskAction", "OverseerToggle", "OverseerShell", "OverseerRun" },
	dependencies = { "nvim-telescope/telescope.nvim" },
	opts = {
		disable_template_modules = { "overseer.template.devenv" },
		task_list = { direction = "bottom", min_height = 8, max_height = 16 },
	},
	config = function(_, opts)
		require("overseer").setup(opts)
		require("config.devenv").setup()
	end,
	keys = {
		{ "<leader>tt", "<cmd>OverseerToggle<cr>", desc = "Task List" },
		{ "<leader>tr", "<cmd>OverseerRun<cr>", desc = "Run Task" },
		{ "<leader>ta", "<cmd>OverseerTaskAction<cr>", desc = "Task Action / Rerun" },
		{ "<leader>ts", "<cmd>OverseerShell<cr>", desc = "Run Shell Task" },
		{
			"<leader>to",
			function()
				require("config.tasks").output()
			end,
			desc = "Project Task Output",
		},
		{
			"<leader>tl",
			function()
				require("config.tasks").rerun()
			end,
			desc = "Rerun Last Project Command",
		},
		{
			"<leader>tp",
			function()
				require("config.tasks").pick()
			end,
			desc = "Project Commands",
		},
	},
}
