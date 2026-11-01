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

return { hostname = read_hostname() }
