local repo, fixture = assert(arg[1]), assert(arg[2]) .. "/" .. vim.uv.hrtime()
for i = 3, 5 do
	vim.opt.runtimepath:append(assert(arg[i]))
end
vim.o.columns, vim.o.lines = 160, 45

local function write(path)
	vim.fn.mkdir(vim.fs.dirname(fixture .. path), "p")
	vim.fn.writefile({}, fixture .. path)
end

write("/client/src/main/kotlin/example/client/Client.kt")
write("/server/src/main/kotlin/example/server/Server.kt")
write("/README.md")

local opts = dofile(repo .. "/configs/nvim/lua/plugins/navigation.lua")[1].opts
opts.enable_git_status, opts.enable_diagnostics, opts.log_to_file = false, false, false
opts.filesystem.follow_current_file.enabled = false
require("neo-tree").setup(opts)
require("neo-tree").ensure_config()
local manager = require("neo-tree.sources.manager")
local renderer = require("neo-tree.ui.renderer")
renderer.resize_timer_interval = -1
local state = manager.get_state("filesystem")
assert(state.group_empty_dirs and require("neo-tree").config.filesystem.scan_mode == "shallow")

local function item(path, children)
	return {
		id = fixture .. path,
		path = fixture .. path,
		name = vim.fs.basename(path),
		type = children and "directory" or "file",
		loaded = children ~= nil,
		children = children,
	}
end

local function initial()
	local client = item("/client", { item("/client/Client.kt") })
	client._is_expanded = true
	return {
		item("", {
			client,
			item("/server", {}),
			item("/README.md"),
		}),
	}
end

state.path = fixture
renderer.show_nodes(initial(), state)
local client = assert(state.tree:get_node(fixture .. "/client"))
client:expand()
state.tree:render()
client.extra = { marker = "preserve metadata" }
renderer.show_nodes({ item("/server/src", {}) }, state, fixture .. "/server")
local preserved = assert(state.tree:get_node(fixture .. "/client/Client.kt"), "grouping lost a sibling's loaded child")
assert(preserved:get_parent_id() == fixture .. "/client")
client = assert(state.tree:get_node(fixture .. "/client"))
assert(client:is_expanded(), "grouping collapsed an expanded sibling")
assert(client.extra.marker == "preserve metadata")
assert(state.tree:get_node(fixture .. "/server/src").name == "server/src")
assert(not state.tree:get_node(fixture .. "/server"), "grouping left the old directory in the tree")
renderer.show_nodes({ item("/server/src/main", {}) }, state, fixture .. "/server/src")
assert(state.tree:get_node(fixture .. "/client/Client.kt"), "repeated grouping lost a sibling's child")
renderer.show_nodes(initial(), state)
assert(state.tree:get_node(fixture .. "/README.md"), "refresh failed after grouping")
renderer.show_nodes(initial()[1].children, state)
state.tree:get_node(fixture .. "/client"):collapse()
state.tree:render()
renderer.show_nodes({ item("/server/src", {}) }, state, fixture .. "/server")
assert(state.tree:get_node(fixture .. "/client/Client.kt"), "root grouping lost a sibling's child")
assert(not state.tree:get_node(fixture .. "/client"):is_expanded(), "grouping expanded a collapsed sibling")
renderer.show_nodes(initial(), state)
manager.dispose("filesystem")

state = manager.get_state("filesystem")
local filesystem = require("neo-tree.sources.filesystem")
local function navigate(path)
	local completed = false
	filesystem.navigate(state, fixture, fixture .. path, function()
		completed = true
	end)
	assert(
		vim.wait(5000, function()
			return completed and state._ready
		end, 10),
		"filesystem navigation did not finish: " .. path
	)
	assert(state.tree:get_node(fixture .. path), "navigation lost the requested file: " .. path)
end

for _ = 1, 3 do
	navigate("/client/src/main/kotlin/example/client/Client.kt")
	navigate("/server/src/main/kotlin/example/server/Server.kt")
end
manager.dispose("filesystem")
print("tree grouping passed: sibling descendants, expansion, metadata, root grouping, refresh, and JVM navigation")
