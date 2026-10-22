return {
	"stevearc/overseer.nvim",
	cmd = { "OverseerRun", "OverseerToggle", "OverseerShell", "OverseerTaskAction" },
	opts = { task_list = { direction = "bottom", min_height = 8, max_height = 16 } },
	keys = {
		{ "<leader>tt", "<cmd>OverseerToggle<cr>", desc = "Task List" },
		{ "<leader>tr", "<cmd>OverseerRun<cr>", desc = "Run Task" },
		{ "<leader>ta", "<cmd>OverseerTaskAction<cr>", desc = "Task Action / Rerun" },
		{ "<leader>ts", "<cmd>OverseerShell<cr>", desc = "Run Shell Task" },
		{
			"<leader>tp",
			function()
				require("config.tasks").pick()
			end,
			desc = "Project Commands",
		},
	},
}
