local M = {}

-- lock workspaces 1-10 to DP-1 and 11-20 to DP-2
for i = 1, 10 do
	hl.workspace_rule({ workspace = tostring(i), monitor = "DP-1" })
	hl.workspace_rule({ workspace = tostring(i + 10), monitor = "DP-2" })
end

function M.bind_workspace(i)
	local key = tostring(i % 10)

	local function offset()
		local mon = hl.get_active_monitor()
		return (mon and mon.name == "DP-2") and 10 or 0
	end

	-- switch to workspace on current monitor
	hl.bind(Mod .. " + " .. key, function()
		hl.dispatch(hl.dsp.focus({ workspace = i + offset() }))
	end)

	-- move window to workspace, stay on current
	hl.bind(Mod .. " + SHIFT + " .. key, function()
		local ws = hl.get_active_workspace()
		if not ws then
			return
		end
		local current = ws.id
		hl.dispatch(hl.dsp.window.move({ workspace = i + offset() }))
		hl.dispatch(hl.dsp.focus({ workspace = current }))
	end)

	-- move window to workspace and follow
	hl.bind(Mod .. " + CTRL + " .. key, function()
		local target = i + offset()
		hl.dispatch(hl.dsp.window.move({ workspace = target }))
		hl.dispatch(hl.dsp.focus({ workspace = target }))
	end)
end

return M
