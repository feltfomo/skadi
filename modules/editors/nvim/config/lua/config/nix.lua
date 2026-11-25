local M = {}

local function literal(value)
	return (vim.json.encode(value):gsub("%${", "\\${"))
end

-- nixpkgs as the repository's lock pins it, fetched by itself. fetching the repository to reach
-- `inputs.nixpkgs` would copy the checkout into the store first, and a bare path copies everything
-- on disk, build output included: a Rust worktree's `target/` made each copy several gigabytes.
local function locked_nixpkgs(root)
	local ok, lock = pcall(function()
		return vim.json.decode(table.concat(vim.fn.readfile(root .. "/flake.lock"), "\n"))
	end)
	if not ok or type(lock) ~= "table" or type(lock.nodes) ~= "table" then
		return nil
	end
	local inputs = (lock.nodes[lock.root] or {}).inputs or {}
	local name = inputs.nixpkgs
	local node = type(name) == "string" and lock.nodes[name] or nil
	if not node or type(node.locked) ~= "table" then
		return nil
	end
	return "builtins.fetchTree (builtins.fromJSON " .. literal(vim.json.encode(node.locked)) .. ")"
end

-- only a repository that defines NixOS hosts has options to offer, and only it is fetched, as Git,
-- so the copy holds what Git tracks: a file Git has never seen needs `git add -N` first, as it does
-- for a switch.
local function defines_hosts(root)
	local grep = vim.system({ "git", "-C", root, "grep", "-q", "nixosConfigurations" }):wait()
	return grep.code == 0
end

function M.settings(root)
	if not root or vim.fn.filereadable(root .. "/flake.nix") ~= 1 then
		return {}
	end
	local nixpkgs = locked_nixpkgs(root)
	local settings = {
		nixpkgs = { expr = "import (" .. (nixpkgs or "<nixpkgs>") .. ") {}" },
	}
	if defines_hosts(root) then
		local flake = "(builtins.getFlake " .. literal("git+file://" .. root) .. ")"
		local config = flake .. ".nixosConfigurations." .. literal(vim.uv.os_gethostname())
		settings.options = {
			nixos = { expr = config .. ".options or {}" },
			home_manager = {
				expr = "(" .. config .. ".options.home-manager.users.type.getSubOptions or (_: {})) []",
			},
		}
	end
	return settings
end

return M
