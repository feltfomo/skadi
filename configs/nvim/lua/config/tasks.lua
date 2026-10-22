local M = {}

function M.pick()
	local root = require("config.project").root()
	local tasks = {}
	if vim.fn.filereadable(root .. "/devenv.nix") == 1 then
		for _, name in ipairs({ "odyssey-check", "odyssey-test", "odyssey-helios", "odyssey-gate" }) do
			-- Only offer repository-owned commands that this shell actually provides.
			if vim.fn.executable(name) == 1 then
				tasks[#tasks + 1] = { name = name, cmd = { name } }
			end
		end
	end
	if vim.fn.executable(root .. "/gradlew") == 1 then
		for _, name in ipairs({ "test", "detekt", "qualityGate" }) do
			tasks[#tasks + 1] = { name = "Gradle " .. name, cmd = { "./gradlew", "--console=plain", name } }
		end
	end
	local module = require("config.project").module_root()
	if vim.fn.filereadable(module .. "/Cargo.toml") == 1 then
		for _, command in ipairs({ { "test", "--all-targets" }, { "clippy", "--all-targets" } }) do
			tasks[#tasks + 1] =
				{ name = "Cargo " .. command[1], cmd = vim.list_extend({ "cargo" }, command), cwd = module }
		end
	end
	if #tasks == 0 then
		vim.notify("Open this project inside its development shell to use its commands.", vim.log.levels.INFO)
		return
	end
	vim.ui.select(tasks, {
		prompt = "Project command",
		format_item = function(task)
			return task.name
		end,
	}, function(choice)
		if not choice then
			return
		end
		local log = vim.fn.stdpath("state")
			.. "/tasks/"
			.. vim.fn.sha256(root):sub(1, 12)
			.. "/"
			.. os.date("%Y%m%d-%H%M%S")
			.. "-"
			.. vim.uv.hrtime()
			.. ".log"
		local overseer = require("overseer")
		local task = overseer.new_task({
			name = choice.name,
			cmd = choice.cmd,
			cwd = choice.cwd or root,
			components = { { "on_output_write_file", filename = log }, "default" },
		})
		task:start()
		overseer.open()
	end)
end

return M
