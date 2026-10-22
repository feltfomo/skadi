local repo = assert(arg[1], "pass the repository root")
local fixture = assert(arg[2], "pass a scratch directory") .. "/" .. vim.uv.hrtime()
package.path = repo .. "/configs/nvim/lua/?.lua;" .. package.path
vim.opt.runtimepath:prepend(repo .. "/configs/nvim")
vim.fn.mkdir(fixture .. "/nested", "p")
vim.fn.writefile({ "{}" }, fixture .. "/devenv.nix")
vim.fn.writefile({}, fixture .. "/.git")

local real_system, real_executable = vim.system, vim.fn.executable
local jobs = {}
vim.system = function(argv, opts, cb)
	assert(not opts or opts.cwd == fixture or opts.cwd == fixture .. "/nested")
	jobs[#jobs + 1] = { argv = argv, cb = cb }
	return {}
end
vim.fn.executable = function(name)
	return name == "devenv" and 1 or 0
end

local devenv = require("config.devenv")
assert(devenv.root(fixture .. "/nested") == fixture)
local function complete(index, data, code)
	jobs[index].cb({ code = code or 0, stdout = vim.json.encode(data), stderr = "fixture error" })
	vim.wait(100, function()
		return false
	end, 10)
end
local tasks = {
	{ name = "check:all", after = { "check:one" }, description = "aggregate", hasExec = false },
	{ name = "devenv:enterShell", before = { "check:one" } },
}
local scripts = { scripts = { greet = { exec = 'printf "%s" "$@"', description = "greet someone" } } }
local calls = 0
local function discovered(items, err)
	assert(not err, err)
	assert(#items == 3, vim.inspect(items))
	assert(items[1].kind == "Script" and items[1].description == "greet someone")
	assert(items[2].details.after[1] == "check:one")
	assert(items[3].internal)
	calls = calls + 1
end

devenv.discover(fixture, discovered)
devenv.discover(fixture, discovered)
assert(#jobs == 1 and calls == 0, "discovery blocked or duplicated an in-flight request")
assert(vim.deep_equal(jobs[1].argv, { "devenv", "--no-tui", "tasks", "list", "--json" }))
complete(1, tasks)
assert(#jobs == 2 and calls == 0, "evaluations must serialize")
assert(vim.deep_equal(jobs[2].argv, { "devenv", "--no-tui", "eval", "scripts" }))
complete(2, scripts)
assert(calls == 2)
devenv.discover(fixture, discovered)
vim.wait(100, function()
	return calls == 3
end)
assert(calls == 3 and #jobs == 2, "cache miss")

devenv.setup()
vim.api.nvim_exec_autocmds("BufWritePost", { pattern = fixture .. "/imported.nix" })
devenv.discover(fixture, discovered)
assert(#jobs == 3, "saving an imported module did not invalidate discovery")
devenv.invalidate(fixture .. "/devenv.nix")
complete(3, tasks)
complete(4, scripts)
assert(calls == 3 and #jobs == 5, "stale in-flight result was delivered")
complete(5, tasks)
complete(6, scripts)
assert(calls == 4)

vim.fn.writefile({ "{", "  changed = true;", "}" }, fixture .. "/devenv.nix")
devenv.discover(fixture, discovered)
assert(#jobs == 7, "external config changes did not invalidate discovery")
complete(7, tasks)
complete(8, scripts)
assert(calls == 5)

local failed = false
devenv.discover(fixture, function(items, err)
	assert(#items == 1 and err:find("fixture error", 1, true))
	failed = true
end, true)
complete(9, {}, 1)
complete(10, scripts)
assert(failed, "partial failure was swallowed")
devenv.discover(fixture, discovered)
assert(#jobs == 11, "failure was cached as success")
complete(11, tasks)
complete(12, scripts)

local refreshed = false
devenv.discover(fixture, function(items, err)
	assert(not err and #items == 3)
	refreshed = true
end)
devenv.invalidate(fixture .. "/imported.nix")
vim.wait(100, function()
	return #jobs == 13
end)
assert(not refreshed and #jobs == 13, "scheduled cache callback delivered invalidated data")
complete(13, tasks)
complete(14, scripts)
assert(refreshed)

local clock = vim.uv.hrtime
vim.uv.hrtime = function()
	return clock() + 61 * 1e9
end
devenv.discover(fixture, discovered)
assert(#jobs == 15, "expired discovery did not refresh")
complete(15, tasks)
complete(16, scripts)
vim.uv.hrtime = clock

local malformed = false
devenv.discover(fixture, function(items, err)
	assert(#items == 1 and err:find("invalid JSON", 1, true))
	malformed = true
end, true)
jobs[17].cb({ code = 0, stdout = "not JSON" })
vim.wait(100, function()
	return #jobs == 18
end)
complete(18, scripts)
assert(malformed, "malformed metadata was accepted")

local missing = false
vim.fn.executable = function()
	return 0
end
devenv.discover(fixture .. "/nested", function(items, err)
	assert(#items == 0 and err:find("not on PATH", 1, true))
	missing = true
end)
vim.wait(100, function()
	return missing
end)
assert(missing)
vim.system, vim.fn.executable = real_system, real_executable

local task_config = require("config.tasks")
local args = assert(task_config.parse_args(' ["two words", "$(touch sentinel)", "a;b", "", "--flag"] '))
assert(not task_config.parse_args("{}"))
assert(not task_config.parse_args('["ok", 3]'))
assert(not task_config.parse_args('["\\u0000"]'))
assert(not task_config.parse_args('"hello"'))
assert(not task_config.parse_args("bad input"))
assert(vim.deep_equal(task_config.parse_args("[]"), {}))
assert(vim.deep_equal(devenv.command({ kind = "Script", name = "greet" }, args), {
	"devenv",
	"--no-tui",
	"shell",
	"--",
	"greet",
	"two words",
	"$(touch sentinel)",
	"a;b",
	"",
	"--flag",
}))
assert(vim.deep_equal(devenv.command({ kind = "Task", name = "check:all" }), {
	"devenv",
	"--no-tui",
	"tasks",
	"run",
	"--show-output",
	"check:all",
}))

local original_input, original_notify = vim.ui.input, vim.notify
local prompted, launched = 0, false
vim.notify = function() end
vim.ui.input = function(opts, cb)
	prompted = prompted + 1
	if prompted == 1 then
		assert(opts.default == "[]")
		cb("broken")
	else
		assert(opts.default == "broken", "invalid arguments were lost")
		cb(nil)
	end
end
task_config.prompt_args(function()
	launched = true
end)
vim.wait(100, function()
	return prompted == 2
end)
assert(prompted == 2 and not launched, "cancelled prompt launched a command")
vim.ui.input, vim.notify = original_input, original_notify

local started = {}
package.loaded.overseer = {
	new_task = function(opts)
		local task = { running = false, opts = opts }
		function task:start()
			self.running = true
		end
		function task:open_output(direction)
			assert(direction == "float")
		end
		function task:is_running()
			return self.running
		end
		started[#started + 1] = task
		return task
	end,
}
package.loaded["config.project"] = {
	root = function()
		return fixture
	end,
}
local task = task_config.run({ kind = "Script", name = "greet", cwd = fixture }, fixture, args)
assert(vim.deep_equal(task.opts.cmd, devenv.command({ kind = "Script", name = "greet" }, args)))
assert(task.opts.metadata.project_root == fixture)
vim.notify = function() end
task_config.rerun()
assert(#started == 1, "rerun duplicated a running command")
task.running = false
task_config.rerun()
assert(#started == 2 and vim.deep_equal(started[2].opts.cmd, task.opts.cmd))
assert(started[1].opts.components[1].filename ~= started[2].opts.components[1].filename)
vim.notify = original_notify
print(
	"devenv tasks passed: async discovery, cache races, invalidation, failures, literal argv, cancellation, and reruns"
)
