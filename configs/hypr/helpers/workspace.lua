local G = require("globals")

local M = {}

-- lock workspaces 1-10 to the left monitor and 11-20 to the right
for i = 1, 10 do
	hl.workspace_rule({ workspace = tostring(i), monitor = G.monitors.left })
	hl.workspace_rule({ workspace = tostring(i + 10), monitor = G.monitors.right })
end

function M.bind_workspace(i)
	local key = tostring(i % 10)

	local function offset()
		local mon = hl.get_active_monitor()
		return (mon and mon.name == G.monitors.right) and 10 or 0
	end

	-- switch to workspace on current monitor
	hl.bind(G.mod .. " + " .. key, function()
		hl.dispatch(hl.dsp.focus({ workspace = i + offset() }))
	end)

	-- move window to workspace, stay on current
	hl.bind(G.mod .. " + SHIFT + " .. key, function()
		local ws = hl.get_active_workspace()
		if not ws then
			return
		end
		local current = ws.id
		hl.dispatch(hl.dsp.window.move({ workspace = i + offset() }))
		hl.dispatch(hl.dsp.focus({ workspace = current }))
	end)

	-- move window to workspace and follow
	hl.bind(G.mod .. " + CTRL + " .. key, function()
		local target = i + offset()
		hl.dispatch(hl.dsp.window.move({ workspace = target }))
		hl.dispatch(hl.dsp.focus({ workspace = target }))
	end)
end

return M