return {
	"lewis6991/gitsigns.nvim",
	event = { "BufReadPre", "BufNewFile" },
	opts = {
		signs = {
			add = { text = "┃" },
			change = { text = "┃" },
			delete = { text = "▁" },
			topdelete = { text = "▔" },
			changedelete = { text = "~" },
			untracked = { text = "┆" },
		},
		on_attach = function(bufnr)
			local gitsigns = require("gitsigns")
			local function map(mode, lhs, rhs, desc)
				vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, silent = true, desc = desc })
			end

			map("n", "]h", function()
				if vim.wo.diff then
					vim.cmd.normal({ "]c", bang = true })
				else
					gitsigns.nav_hunk("next")
				end
			end, "Next Git Hunk")
			map("n", "[h", function()
				if vim.wo.diff then
					vim.cmd.normal({ "[c", bang = true })
				else
					gitsigns.nav_hunk("prev")
				end
			end, "Previous Git Hunk")
			map("n", "<leader>hs", gitsigns.stage_hunk, "Stage Git Hunk")
			map("x", "<leader>hs", function()
				gitsigns.stage_hunk({ vim.fn.line("."), vim.fn.line("v") })
			end, "Stage Git Hunk")
			map("n", "<leader>hr", gitsigns.reset_hunk, "Reset Git Hunk")
			map("x", "<leader>hr", function()
				gitsigns.reset_hunk({ vim.fn.line("."), vim.fn.line("v") })
			end, "Reset Git Hunk")
			map("n", "<leader>hS", gitsigns.stage_buffer, "Stage Git Buffer")
			map("n", "<leader>hu", gitsigns.undo_stage_hunk, "Undo Staged Git Hunk")
			map("n", "<leader>hR", gitsigns.reset_buffer, "Reset Git Buffer")
			map("n", "<leader>hp", gitsigns.preview_hunk_inline, "Preview Git Hunk")
			map("n", "<leader>hb", function()
				gitsigns.blame_line({ full = true })
			end, "Blame Git Line")
			map("n", "<leader>hd", gitsigns.diffthis, "Diff Git Index")
			map("n", "<leader>hD", function()
				gitsigns.diffthis("~")
			end, "Diff Git Parent")
			map("n", "<leader>hq", gitsigns.setqflist, "Git Hunks")
			map({ "o", "x" }, "ih", gitsigns.select_hunk, "Git Hunk")
		end,
	},
}
