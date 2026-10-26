return {
	"oclay1st/gradle.nvim",
	cmd = { "Gradle", "GradleExec", "GradleInit", "GradleFavorites" },
	dependencies = { "MunifTanjim/nui.nvim" },
	opts = {
		-- the project wrapper keeps task execution on the repository's pinned gradle
		gradle_executable = "./gradlew",
		project_scanner_depth = 5,
		projects_view = {
			custom_commands = {
				{
					name = "quality gate",
					cmd_args = { "qualityGate" },
					description = "run compiler checks, tests, and detekt",
				},
				{
					name = "tests",
					cmd_args = { "test" },
					description = "run the gradle test suite",
				},
				{
					name = "detekt",
					cmd_args = { "detekt" },
					description = "run kotlin static analysis",
				},
			},
		},
		console = {
			open_in_tabpage = false,
		},
	},
	keys = {
		{ "<leader>G", desc = "Gradle" },
		{ "<leader>Gg", "<cmd>Gradle<cr>", desc = "Gradle Projects" },
		{ "<leader>Ge", "<cmd>GradleExec<cr>", desc = "Execute Gradle Task" },
		{ "<leader>Gf", "<cmd>GradleFavorites<cr>", desc = "Gradle Favorites" },
	},
}
