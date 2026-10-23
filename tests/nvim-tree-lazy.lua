local repo, fixture = assert(arg[1]), assert(arg[2]) .. "/" .. vim.uv.hrtime()
vim.o.loadplugins = true
vim.env.NVIM_NEO_TREE_DIR = assert(arg[3])
vim.opt.runtimepath:prepend(assert(arg[7]))
local spec = dofile(repo .. "/configs/nvim/lua/plugins/navigation.lua")[1]
spec.opts.log_to_file = false
spec.dependencies = {
	{ "MunifTanjim/nui.nvim", dir = assert(arg[4]) },
	{ "nvim-lua/plenary.nvim", dir = assert(arg[5]) },
	{ "echasnovski/mini.icons", dir = assert(arg[6]) },
}
local pins = vim.json.decode(table.concat(vim.fn.readfile(repo .. "/configs/nvim/lazy-lock.json"), "\n"))
require("lazy").setup({
	spec = { spec, { "neo-tree.nvim", commit = pins["neo-tree.nvim"].commit, optional = true } },
	root = fixture .. "/plugins",
	lockfile = fixture .. "/lazy-lock.json",
	local_spec = false,
	install = { missing = false },
	checker = { enabled = false },
	change_detection = { enabled = false },
	rocks = { enabled = false },
})
local plugin = require("lazy.core.config").plugins["neo-tree.nvim"]
assert(plugin.dir == arg[3] and plugin._.is_local)
require("lazy").sync({ plugins = { "neo-tree.nvim" }, wait = true, show = false })
for _, task in ipairs(plugin._.tasks or {}) do
	assert(not task:has_errors(), task.name .. ": " .. task:output())
end
assert(require("neo-tree").ensure_config().filesystem.group_empty_dirs)
vim.cmd.help("neo-tree")
assert(vim.api.nvim_buf_get_name(0) == plugin.dir .. "/help/doc/neo-tree.txt", "packaged help is unavailable")
print("tree packaging passed: Lazy sync, immutable source, grouped directories, and help lookup")
