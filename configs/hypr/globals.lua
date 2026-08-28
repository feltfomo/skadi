-- reading the hostname directly avoids a subprocess on every reload
local function read_hostname()
	local file = io.open("/etc/hostname", "r")
	if not file then
		return "unknown"
	end

	local name = file:read("*l")
	file:close()
	return name or "unknown"
end

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
