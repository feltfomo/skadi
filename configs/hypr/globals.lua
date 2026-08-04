-- read the hostname without leaking a process handle (the old io.popen never
-- closed it). /etc/hostname exists on every NixOS host and holds exactly the
-- name, so this needs no Nix-generated file and can't drop us into emergency
-- mode if that file is missing.
local function read_hostname()
	local f = io.open("/etc/hostname", "r")
	if not f then
		return "unknown"
	end
	local name = f:read("*l")
	f:close()
	return name or "unknown"
end

-- single config namespace. every module does `local G = require("globals")`
-- instead of relying on bare globals, so load order is not load-bearing.
local G = {
	mod = "SUPER",
	mod_alt = "SUPER + ALT",
	terminal = "kitty",
	screenshot = "hyprshot -m region --raw | satty --filename -",
	hostname = read_hostname(),
	clipboard = "caelestia clipboard",
	directions = {
		right = { arrow = "right", vim = "l" },
		left = { arrow = "left", vim = "h" },
		up = { arrow = "up", vim = "k" },
		down = { arrow = "down", vim = "j" },
	},
	monitors = {
		left = "DP-1",
		right = "DP-2",
	},
}

return G
