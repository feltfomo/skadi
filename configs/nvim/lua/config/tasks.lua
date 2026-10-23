local M = {}
local latest = {}

local function project_root()
	local id = vim.b.overseer_task
	local task = id and require("overseer.task_list").get(id)
	return task and task.metadata.project_root or require("config.project").root()
end

local function notify(message)
	vim.notify(message, vim.log.levels.WARN)
end

function M.run(choice, root, args)
	local command = choice.cmd or require("config.devenv").command(choice, args)
	local log = vim.fn.stdpath("state")
		.. "/tasks/"
		.. vim.fn.sha256(root):sub(1, 12)
		.. "/"
		.. os.date("%Y%m%d-%H%M%S")
		.. "-"
		.. vim.uv.hrtime()
		.. ".log"
	local task = require("overseer").new_task({
		name = choice.kind .. " " .. choice.name,
		cmd = vim.deepcopy(command),
		cwd = choice.cwd or root,
		metadata = { project_root = root },
		default_component_params = { errorformat = require("config.task_output").errorformat },
		components = {
			{ "on_output_write_file", filename = log },
			{ "on_output_quickfix", items_only = true, set_diagnostics = true, tail = false },
			"on_exit_set_status",
			"on_complete_notify",
		},
	})
	latest[root] = { choice = vim.deepcopy(choice), args = vim.deepcopy(args), task = task }
	task:start()
	task:open_output("float")
	return task
end

function M.rerun()
	local root = project_root()
	local last = latest[root]
	if not last then
		notify("No project command to rerun in this repository.")
	elseif last.task:is_running() then
		notify("The last project command is still running. Stop it in the task list first.")
	else
		M.run(last.choice, root, last.args)
	end
end

function M.output()
	local sidebar = require("overseer.task_list.sidebar").get()
	local task = sidebar and sidebar.bufnr == vim.api.nvim_get_current_buf() and sidebar:get_task_from_line()
	if not task then
		local last = latest[project_root()]
		task = last and last.task
	end
	if task and not task:is_disposed() then
		task:open_output("float")
	else
		notify("No project command output available. Select a task in the task list first.")
	end
end

function M.fallback(root, module)
	local tasks = {}
	if vim.fn.executable(root .. "/gradlew") == 1 then
		for _, name in ipairs({ "qualityGate", "detekt", "test" }) do
			tasks[#tasks + 1] = { kind = "Gradle", name = name, cmd = { "./gradlew", "--console=plain", name } }
		end
	end
	if vim.fn.filereadable(module .. "/Cargo.toml") == 1 then
		for _, name in ipairs({ "clippy", "test" }) do
			tasks[#tasks + 1] = { kind = "Cargo", name = name, cmd = { "cargo", name, "--all-targets" }, cwd = module }
		end
	end
	return tasks
end

function M.parse_args(input)
	local ok, args = pcall(vim.json.decode, input)
	if not ok or type(args) ~= "table" or not vim.islist(args) or not input:match("^%s*%[") then
		return nil, 'Use a JSON array of strings, for example ["--name", "two words"].'
	end
	for _, value in ipairs(args) do
		if type(value) ~= "string" or value:find("%z") then
			return nil, "Each argument must be a string without NUL characters."
		end
	end
	return args
end

function M.prompt_args(callback, previous)
	vim.ui.input({
		prompt = 'Arguments, e.g. ["--name", "two words"]: ',
		default = previous or "[]",
	}, function(input)
		if not input then
			return
		end
		local args, err = M.parse_args(input)
		if args then
			callback(args)
		else
			notify(err)
			vim.schedule(function()
				M.prompt_args(callback, input)
			end)
		end
	end)
end

local function preview(choice, root)
	local lines = { choice.kind .. " " .. choice.name, "" }
	vim.list_extend(lines, vim.split(choice.description or "No description declared.", "\n", { plain = true }))
	lines[#lines + 1] = ""
	local command = choice.cmd or require("config.devenv").command(choice)
	lines[#lines + 1] = "Directory: " .. (choice.cwd or root)
	lines[#lines + 1] = "Command: " .. table.concat(vim.tbl_map(vim.fn.shellescape, command), " ")
	local details = choice.details or {}
	for _, key in ipairs({ "after", "before", "wantedBy" }) do
		if details[key] and #details[key] > 0 then
			lines[#lines + 1] = key .. ": " .. table.concat(details[key], ", ")
		end
	end
	if details.exec then
		vim.list_extend(lines, { "", "Script body:" })
		vim.list_extend(lines, vim.split(details.exec, "\n", { plain = true }))
	end
	return lines
end

function M.pick()
	local project = require("config.project")
	local root = project_root()
	local devenv = require("config.devenv")
	local name = vim.api.nvim_buf_get_name(0)
	local devenv_root = devenv.root(vim.bo.buftype == "" and name ~= "" and name or root)
	local fallback = M.fallback(root, project.module_root())
	local discovered, show_all, loading = {}, false, devenv_root ~= nil
	local actions = require("telescope.actions")
	local state = require("telescope.actions.state")
	local finders = require("telescope.finders")
	local picker
	local function finder()
		local items = vim.deepcopy(fallback)
		for _, item in ipairs(discovered) do
			if show_all or not item.internal then
				items[#items + 1] = item
			end
		end
		return finders.new_table({
			results = items,
			entry_maker = function(item)
				local label = string.format("%-6s %s", item.kind, item.name)
				return { value = item, display = label, ordinal = label .. " " .. (item.description or "") }
			end,
		})
	end
	local function update()
		if picker and picker.prompt_bufnr and vim.api.nvim_buf_is_valid(picker.prompt_bufnr) then
			picker:refresh(finder(), { reset_prompt = false })
			picker.prompt_border:change_title(
				loading and "Project commands: discovering devenv…" or "Project commands"
			)
		end
	end
	local function discover(refresh)
		if not devenv_root then
			notify("No devenv.nix found above the current file.")
			return
		end
		loading = true
		update()
		devenv.discover(devenv_root, function(items, err)
			discovered, loading = items, false
			update()
			if err then
				notify(err)
			end
		end, refresh)
	end
	picker = require("telescope.pickers").new({}, {
		prompt_title = loading and "Project commands: discovering devenv…" or "Project commands",
		results_title = "Enter run · C-e script args · C-r refresh · C-a internal tasks",
		finder = finder(),
		sorter = require("telescope.config").values.generic_sorter({}),
		previewer = require("telescope.previewers").new_buffer_previewer({
			define_preview = function(self, entry)
				vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, preview(entry.value, root))
			end,
		}),
		attach_mappings = function(prompt, map)
			local function select(with_args)
				local entry = state.get_selected_entry()
				if not entry then
					return
				end
				if with_args and entry.value.kind ~= "Script" then
					notify("Arguments are available for scripts. Enter runs a task with its declared dependencies.")
					return
				end
				actions.close(prompt)
				if with_args then
					M.prompt_args(function(args)
						M.run(entry.value, root, args)
					end)
				else
					M.run(entry.value, root)
				end
			end
			actions.select_default:replace(function()
				select(false)
			end)
			for _, mode in ipairs({ "i", "n" }) do
				map(mode, "<C-e>", function()
					select(true)
				end)
				map(mode, "<C-r>", function()
					discover(true)
				end)
				map(mode, "<C-a>", function()
					show_all = not show_all
					update()
				end)
			end
			return true
		end,
	})
	picker:find()
	if devenv_root then
		discover(false)
	end
end

return M
