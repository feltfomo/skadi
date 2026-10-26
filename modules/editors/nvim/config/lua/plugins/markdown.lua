return {
	"MeanderingProgrammer/render-markdown.nvim",
	dependencies = { "nvim-treesitter/nvim-treesitter", "echasnovski/mini.icons" },
	ft = "markdown",
	cmd = "RenderMarkdown",
	opts = {
		heading = { sign = false, width = "block" },
		code = { sign = false, width = "block" },
		pipe_table = { preset = "round", cell = "padded", wrap = true },
		latex = { enabled = false },
	},
	keys = {
		{ "<leader>mp", "<cmd>RenderMarkdown preview<cr>", desc = "Markdown Side Preview" },
		{ "<leader>mt", "<cmd>RenderMarkdown buf_toggle<cr>", desc = "Toggle Markdown Rendering" },
	},
	config = function(_, opts)
		require("render-markdown").setup(opts)
		vim.api.nvim_create_autocmd("FileType", {
			group = vim.api.nvim_create_augroup("markdown_reading", { clear = true }),
			pattern = "markdown",
			callback = function()
				vim.opt_local.wrap = true
				vim.opt_local.linebreak = true
				vim.opt_local.breakindent = true
			end,
		})
	end,
}
