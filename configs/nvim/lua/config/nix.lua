local M = {}

local function literal(value)
	return (vim.json.encode(value):gsub("%${", "\\${"))
end

function M.settings(root)
	if not root or vim.fn.filereadable(root .. "/flake.nix") ~= 1 then
		return {}
	end
	local flake = "(builtins.getFlake " .. literal(root) .. ")"
	local config = flake .. ".nixosConfigurations." .. literal(vim.uv.os_gethostname())
	return {
		nixpkgs = { expr = "import (" .. flake .. ".inputs.nixpkgs or <nixpkgs>) {}" },
		options = {
			nixos = { expr = config .. ".options or {}" },
			home_manager = {
				expr = "(" .. config .. ".options.home-manager.users.type.getSubOptions or (_: {})) []",
			},
		},
	}
end

return M
