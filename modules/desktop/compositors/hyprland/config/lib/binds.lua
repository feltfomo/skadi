-- hyprland runtime behavior the shared bindings call: scrolling-aware focus, swap, monitor moves,
-- column widths, maximize and layout switching.
local workspace = require("lib.workspace")

local B = {}

B.configureRouting = workspace.configure
B.workspace = workspace.dispatch
B.workspace_step = workspace.step

local function scrolling()
	local current = hl.get_active_workspace()
	local window = hl.get_active_window()
	return current and current.tiled_layout == "scrolling" and window and not window.floating
end

function B.focus(direction)
	local focus = hl.dsp.focus({ direction = direction })
	local scroll = hl.dsp.layout("focus " .. direction)
	return function()
		-- scrolling's dispatcher advances the tape within the current workspace.
		hl.dispatch(scrolling() and scroll or focus)
	end
end

local column_directions = {
	right = { left = "l", right = "r" },
	left = { left = "r", right = "l" },
	down = { up = "l", down = "r" },
	up = { up = "r", down = "l" },
}

local swap_column = { l = hl.dsp.layout("swapcol l"), r = hl.dsp.layout("swapcol r") }

function B.swap(direction)
	local swap = hl.dsp.window.swap({ direction = direction })
	return function()
		local column = scrolling()
			and column_directions[workspace.scroll_direction(hl.get_active_workspace())][direction]
		-- column order remains available when the adjacent window is offscreen
		hl.dispatch(column and swap_column[column] or swap)
	end
end

function B.monitor_move(direction)
	local move = hl.dsp.window.move({ monitor = direction, follow = true })
	return function()
		local window = hl.get_active_window()
		local source_monitor = window and window.monitor and window.monitor.name
		local source_width = scrolling() and window.fullscreen ~= 2 and window.layout.column.width
		hl.dispatch(move)
		if not window or window.floating or not window.monitor or window.monitor.name == source_monitor then
			return
		end
		if not window.workspace or window.workspace.tiled_layout ~= "scrolling" then
			return
		end
		if source_width then
			hl.dispatch(hl.dsp.layout("colresize " .. source_width))
		end

		local travel = column_directions[workspace.scroll_direction(window.workspace)][direction]
		if not travel then
			return
		end

		local index = window.layout.column.index
		local swaps, swap = index, swap_column.l
		if travel == "l" then
			local last_index = index
			for _, other in ipairs(hl.get_workspace_windows(window.workspace)) do
				local layout = other.layout
				if not other.floating and layout.column then
					last_index = math.max(last_index, layout.column.index)
				end
			end
			swaps, swap = last_index - index, swap_column.r
		end
		-- enter the destination strip from the crossed monitor edge, rather than beside its focused column.
		for _ = 1, swaps do
			hl.dispatch(swap)
		end
	end
end

function B.column_width(width)
	local resize = hl.dsp.layout("colresize " .. width)
	local unmaximize = hl.dsp.window.fullscreen({ mode = "maximized", action = "unset" })
	return function()
		if scrolling() then
			hl.dispatch(unmaximize)
			hl.dispatch(resize)
		end
	end
end

function B.maximize()
	local maximize = hl.dsp.window.fullscreen({ mode = "maximized" })
	return function()
		local window = hl.get_active_window()
		if not scrolling() or window.fullscreen == 2 then
			hl.dispatch(maximize)
			return
		end

		-- maximized columns trigger fullscreen fades that break the continuous scrolling strip
		local width = 1.0
		if window.fullscreen ~= 1 and window.layout.column.width >= 1.0 then
			width = hl.get_config("scrolling.column_width")
		end
		B.column_width(width)()
	end
end

function B.layout(name, direction)
	local widen = hl.dsp.layout("colresize 1.0")
	return function()
		local window = hl.get_active_window()
		local maximized = name == "scrolling" and window and window.fullscreen == 1
		workspace.select_layout(hl.get_active_workspace(), name, direction)
		if maximized then
			-- the swap clears maximized state and is deferred, so the full-width column is set after it
			hl.timer(function()
				hl.dispatch(widen)
			end, { timeout = 1, type = "oneshot" })
		end
	end
end

return B
