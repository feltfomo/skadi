-- must be set before lazy loads plugin keymaps, so it goes first.
vim.g.mapleader = " "
vim.g.maplocalleader = " "

vim.opt.clipboard = "unnamedplus"

-- shiftwidth defaults to tabstop (8) when unset, and treesitter's indentexpr
-- multiplies by it, so nix's nested attrsets blow up without this.
vim.opt.expandtab = true
vim.opt.shiftwidth = 2
vim.opt.tabstop = 2
vim.opt.softtabstop = 2

require("config.lazy")
