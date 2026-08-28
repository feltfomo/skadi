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

require("config.lazy")

-- rendered into colors/reactive.lua by noctalia at runtime, so it is missing
-- until the first render on a fresh boot. fall back once, not every boot.
if not pcall(vim.cmd.colorscheme, "reactive") then
	vim.cmd.colorscheme("habamax")
end
