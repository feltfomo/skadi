local M = {}
local cache = {}
local ttl = 60 * 1e9

function M.root(path)
	return vim.fs.root(path, "devenv.nix")
end

local function signature(root)
	local parts = {}
	for _, name in ipairs({ "devenv.local.nix", "devenv.yaml", "devenv.lock", "devenv.nix" }) do
		local stat = vim.uv.fs_stat(root .. "/" .. name)
		parts[#parts + 1] = stat and (stat.size .. ":" .. stat.mtime.sec .. ":" .. stat.mtime.nsec) or "missing"
	end
	return table.concat(parts, "|")
end

function M.invalidate(path)
	for root, entry in pairs(cache) do
		if not path or vim.fs.relpath(root, path) then
			entry.stale = true
		end
	end
end

local function decode(output, label)
	if output.code ~= 0 then
		return nil, label .. " failed: " .. vim.trim(output.stderr or "")
	end
	local ok, data = pcall(vim.json.decode, output.stdout, { luanil = { object = true } })
	if not ok or type(data) ~= "table" then
		return nil, label .. " returned invalid JSON"
	end
	return data
end

function M.command(entry, args)
	if entry.kind == "Task" then
		return { "devenv", "--no-tui", "tasks", "run", "--show-output", entry.name }
	end
	local command = { "devenv", "--no-tui", "shell", "--", entry.name }
	return vim.list_extend(command, args or {})
end

function M.discover(root, callback, refresh)
	local entry = cache[root]
	local stamp = signature(root)
	if entry and entry.stamp ~= stamp then
		entry.stale = true
	end
	if entry and refresh then
		entry.stale = true
	end
	if entry and entry.pending then
		entry.waiters[#entry.waiters + 1] = callback
		return
	end
	if entry and not entry.stale and vim.uv.hrtime() - entry.time < ttl then
		vim.schedule(function()
			if entry.stale or signature(root) ~= entry.stamp then
				M.discover(root, callback)
			else
				callback(vim.deepcopy(entry.items))
			end
		end)
		return
	end
	local waiters = entry and entry.waiters or {}
	waiters[#waiters + 1] = callback
	entry = { stamp = stamp, pending = true, waiters = waiters }
	cache[root] = entry
	local function finish(items, err)
		entry.pending = false
		if entry.stale or signature(root) ~= entry.stamp then
			local callbacks = entry.waiters
			cache[root] = nil
			M.discover(root, function(fresh, failure)
				for _, cb in ipairs(callbacks) do
					cb(vim.deepcopy(fresh), failure)
				end
			end)
			return
		end
		entry.items, entry.time, entry.stale = items, vim.uv.hrtime(), err ~= nil
		local callbacks = entry.waiters
		entry.waiters = {}
		for _, cb in ipairs(callbacks) do
			cb(vim.deepcopy(items), err)
		end
	end
	if vim.fn.executable("devenv") == 0 then
		vim.schedule(function()
			finish({}, "devenv is not on PATH. Install it to discover this project's commands.")
		end)
		return
	end
	local items, errors = {}, {}
	local function run(argv, cb)
		local ok, err = pcall(vim.system, argv, { cwd = root, text = true }, vim.schedule_wrap(cb))
		if not ok then
			vim.schedule(function()
				cb({ code = -1, stderr = tostring(err) })
			end)
		end
	end
	run({ "devenv", "--no-tui", "tasks", "list", "--json" }, function(output)
		local tasks, err = decode(output, "devenv tasks list")
		if tasks and not vim.islist(tasks) then
			tasks, err = nil, "devenv tasks list returned an unexpected JSON shape"
		end
		if err then
			errors[#errors + 1] = err
		end
		for _, task in ipairs(tasks or {}) do
			if type(task) == "table" and type(task.name) == "string" then
				items[#items + 1] = {
					name = task.name,
					kind = "Task",
					description = task.description,
					internal = vim.startswith(task.name, "devenv:"),
					cwd = root,
					details = task,
				}
			end
		end
		-- Serialize evaluations so the two devenv processes don't compete for its cache lock.
		run({ "devenv", "--no-tui", "eval", "scripts" }, function(result)
			local data, failure = decode(result, "devenv eval scripts")
			if data and type(data.scripts) ~= "table" then
				data, failure = nil, "devenv eval scripts returned an unexpected JSON shape"
			end
			if failure then
				errors[#errors + 1] = failure
			end
			for name, script in pairs(data and data.scripts or {}) do
				if type(script) == "table" then
					items[#items + 1] = {
						name = name,
						kind = "Script",
						description = script.description,
						cwd = root,
						details = { exec = script.exec },
					}
				end
			end
			table.sort(items, function(a, b)
				return a.kind .. a.name < b.kind .. b.name
			end)
			finish(items, #errors > 0 and table.concat(errors, "\n") or nil)
		end)
	end)
end

function M.setup()
	vim.api.nvim_create_autocmd("BufWritePost", {
		group = vim.api.nvim_create_augroup("ProjectDevenv", { clear = true }),
		pattern = { "devenv.yaml", "devenv.lock", "*.nix" },
		callback = function(event)
			M.invalidate(event.file)
		end,
	})
end

return M
