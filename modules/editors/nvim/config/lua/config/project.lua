local M = {}

local manifests = { "build.gradle.kts", "build.gradle", "Cargo.toml" }

function M.root(buf)
	local name = vim.api.nvim_buf_get_name(buf or 0)
	local start = name ~= "" and name or vim.fn.getcwd()
	return vim.fs.root(start, ".git")
		or vim.fs.root(start, { "settings.gradle.kts", "settings.gradle", "Cargo.toml", "flake.nix" })
		or vim.fn.getcwd()
end

function M.module_root(buf)
	local name = vim.api.nvim_buf_get_name(buf or 0)
	return vim.fs.root(name ~= "" and name or vim.fn.getcwd(), { manifests }) or M.root(buf)
end

function M.modules(root)
	local command = { "git", "-C", root, "ls-files", "-z", "--cached", "--others", "--exclude-standard", "--" }
	for _, name in ipairs(manifests) do
		vim.list_extend(command, { name, "**/" .. name })
	end
	local result = vim.system(command, { text = true }):wait()
	if result.code ~= 0 then
		return { root }
	end
	local paths, seen = {}, {}
	for _, file in ipairs(vim.split(result.stdout, "\0", { trimempty = true })) do
		local path = vim.fs.dirname(vim.fs.joinpath(root, file))
		if not seen[path] then
			seen[path] = true
			paths[#paths + 1] = path
		end
	end
	table.sort(paths)
	return #paths > 0 and paths or { root }
end

function M.browse(path, reveal)
	require("neo-tree.command").execute({
		action = "focus",
		source = "filesystem",
		dir = path,
		reveal_file = reveal,
	})
end

function M.pick_module(action)
	local root = M.root()
	local actions = require("telescope.actions")
	local state = require("telescope.actions.state")
	require("telescope.pickers")
		.new({}, {
			prompt_title = "Modules: " .. action,
			finder = require("telescope.finders").new_table({
				results = M.modules(root),
				entry_maker = function(path)
					local relative = vim.fs.relpath(root, path)
					local label = (not relative or relative == "." or relative == "") and "[repository]" or relative
					return { value = path, display = label, ordinal = label }
				end,
			}),
			sorter = require("telescope.config").values.generic_sorter({}),
			attach_mappings = function(prompt)
				actions.select_default:replace(function()
					local entry = state.get_selected_entry()
					actions.close(prompt)
					if not entry then
						return
					end
					if action == "browse" then
						M.browse(entry.value)
					else
						require("telescope.builtin")[action]({ cwd = entry.value })
					end
				end)
				return true
			end,
		})
		:find()
end

return M
