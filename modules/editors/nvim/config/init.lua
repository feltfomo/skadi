-- must be set before lazy loads plugin keymaps, so it goes first.
vim.g.mapleader = " "
vim.g.maplocalleader = " "
vim.opt.clipboard = "unnamedplus"
vim.opt.swapfile = false
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.signcolumn = "yes"
vim.opt.expandtab = true
vim.opt.shiftwidth = 2
vim.opt.tabstop = 2
vim.opt.softtabstop = 2
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.scrolloff = 6
vim.opt.sidescrolloff = 4
vim.opt.splitbelow = true
vim.opt.splitright = true
vim.opt.splitkeep = "screen"
vim.opt.inccommand = "split"
vim.opt.updatetime = 250
vim.opt.timeoutlen = 400
vim.opt.undofile = true
vim.opt.cursorline = true
vim.opt.wrap = false
vim.opt.foldmethod = "expr"
vim.opt.foldexpr = "v:lua.vim.treesitter.foldexpr()"
vim.opt.foldlevel = 99
vim.opt.foldlevelstart = 99
vim.opt.confirm = true

-- an ssh or herdr session may have no wayland socket for wl-copy, and herdr doesn't answer
-- osc 52 reads, so a real paste provider would hang every `p` until its timeout.
if vim.env.SSH_CONNECTION or vim.env.HERDR_ENV == "1" then
	local osc52 = require("vim.ui.clipboard.osc52")
	local function internal()
		return { vim.fn.getreg('"', 1, true), vim.fn.getregtype('"') }
	end
	vim.g.clipboard = {
		name = "osc52-copy-only",
		copy = { ["+"] = osc52.copy("+"), ["*"] = osc52.copy("*") },
		paste = { ["+"] = internal, ["*"] = internal },
	}
end

vim.keymap.set("n", "<Esc>", "<cmd>nohlsearch<cr>", { desc = "Clear Search Highlight" })
vim.keymap.set("n", "<C-h>", "<C-w>h", { desc = "Focus Left Window" })
vim.keymap.set("n", "<C-j>", "<C-w>j", { desc = "Focus Lower Window" })
vim.keymap.set("n", "<C-k>", "<C-w>k", { desc = "Focus Upper Window" })
vim.keymap.set("n", "<C-l>", "<C-w>l", { desc = "Focus Right Window" })

require("config.lazy")

-- rendered into colors/reactive.lua by noctalia at runtime, so it is missing
-- until the first render on a fresh boot. fall back once, not every boot.
if not pcall(vim.cmd.colorscheme, "reactive") then
	vim.cmd.colorscheme("habamax")
end
