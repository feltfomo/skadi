local repo, fixture = assert(arg[1]), assert(arg[2]) .. "/" .. vim.uv.hrtime()
vim.opt.runtimepath:prepend(repo .. "/configs/nvim")
vim.opt.runtimepath:append(assert(arg[3]))
vim.opt.runtimepath:append(assert(arg[4]))
vim.o.columns, vim.o.lines = 160, 45
vim.fn.mkdir(fixture, "p")
vim.fn.writefile({}, fixture .. "/.git")
vim.fn.writefile({ "{}" }, fixture .. "/devenv.nix")
vim.cmd.cd(fixture)
vim.bo.buftype = "nofile"
vim.api.nvim_buf_set_name(0, "task://output")

local calls, callbacks = 0, {}
local devenv = require("config.devenv")
devenv.discover = function(root, cb, refresh)
	assert(root == fixture, "special buffer names must fall back to the project root")
	calls = calls + 1
	if calls == 2 then
		assert(refresh, "explicit refresh was lost")
	end
	callbacks[#callbacks + 1] = cb
end
local tasks = require("config.tasks")
local launches = {}
tasks.run = function(choice, root, args)
	launches[#launches + 1] = { choice = choice, root = root, args = args }
end
require("telescope").setup({})
tasks.pick()
assert(calls == 1 and vim.api.nvim_buf_get_option(0, "filetype") == "TelescopePrompt")
local state = require("telescope.actions.state")
local picker = state.get_current_picker(vim.api.nvim_get_current_buf())
local function wait_for(count)
	assert(
		vim.wait(3000, function()
			return picker.manager and picker.manager:num_results() == count
		end, 10),
		"unexpected picker result count"
	)
end
local items = {
	{
		kind = "Script",
		name = "greet",
		description = "hello\nworld",
		cwd = fixture,
		details = { exec = "printf hello" },
	},
	{ kind = "Task", name = "check:all", details = { after = { "check:one" } } },
	{ kind = "Task", name = "devenv:enterShell", internal = true },
}
callbacks[1](items)
wait_for(2)
local function action(key)
	for _, map in ipairs(vim.api.nvim_buf_get_keymap(picker.prompt_bufnr, "i")) do
		if
			vim.api.nvim_replace_termcodes(map.lhs, true, true, true)
			== vim.api.nvim_replace_termcodes(key, true, true, true)
		then
			assert(type(map.callback) == "function")
			map.callback()
			return
		end
	end
	error("missing picker action " .. key)
end
action("<C-a>")
wait_for(3)
action("<C-a>")
wait_for(2)
action("<C-r>")
assert(calls == 2)
callbacks[2](items)
wait_for(2)
picker:set_selection(1)
local entry = state.get_selected_entry()
assert(entry and entry.value.kind == "Script")
local original_input = vim.ui.input
vim.ui.input = function(_, cb)
	cb(nil)
end
action("<C-e>")
assert(#launches == 0, "cancelled script arguments launched a command")
vim.ui.input = original_input

tasks.pick()
picker = state.get_current_picker(vim.api.nvim_get_current_buf())
callbacks[3](items)
wait_for(2)
picker:set_selection(1)
require("telescope.actions").select_default(picker.prompt_bufnr)
assert(#launches == 1 and launches[1].choice.name == "greet" and launches[1].args == nil)
assert(launches[1].root == fixture)
callbacks[3](items)
print("project command picker passed: async refresh, internal toggle, special buffers, cancellation, and Enter")
