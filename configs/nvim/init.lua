-- must be set before lazy loads plugin keymaps, so it goes first.
vim.g.mapleader = " "
vim.g.maplocalleader = " "

require("config.lazy")
