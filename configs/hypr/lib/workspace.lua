local G = require("globals")
local bind = require("lib.bind")

local M = {}

-- each monitor owns a ten-workspace bank
for i = 1, 10 do
	hl.workspace_rule({ workspace = tostring(i), monitor = G.monitors.left, persistent = true })
	hl.workspace_rule({ workspace = tostring(i + 10), monitor = G.monitors.right, persistent = true })
end

function M.bind_workspace(i)
	local key = tostring(i % 10)

	-- number keys address the matching workspace bank on the active monitor
	local function offset()
		local monitor = hl.get_active_monitor()
		return (monitor and monitor.name == G.monitors.right) and 10 or 0
	end

	bind(G.mod, key, function()
		hl.dispatch(hl.dsp.focus({ workspace = i + offset() }))
	end)

	-- shift moves the window without following it
	bind(G.mod .. " + SHIFT", key, function()
		local workspace = hl.get_active_workspace()
		if not workspace then
			return
		end

		local current = workspace.id
		hl.dispatch(hl.dsp.window.move({ workspace = i + offset() }))
		hl.dispatch(hl.dsp.focus({ workspace = current }))
	end)

	-- ctrl moves the window and follows it
	bind(G.mod .. " + CTRL", key, function()
		local target = i + offset()
		hl.dispatch(hl.dsp.window.move({ workspace = target }))
		hl.dispatch(hl.dsp.focus({ workspace = target }))
	end)
end

return M
