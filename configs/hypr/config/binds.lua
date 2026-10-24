local workspace = require("lib.workspace")

local B = {}

B.configureRouting = workspace.configure

local function scrolling()
	local current = hl.get_active_workspace()
	local window = hl.get_active_window()
	return current and current.tiled_layout == "scrolling" and window and not window.floating
end

function B.focus(direction)
	local focus = hl.dsp.focus({ direction = direction })
	local scroll = hl.dsp.layout("focus " .. direction:sub(1, 1))
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

function B.swap(direction)
	local swap = hl.dsp.window.swap({ direction = direction })
	local previous = hl.dsp.layout("swapcol l")
	local next_column = hl.dsp.layout("swapcol r")
	return function()
		if scrolling() then
			local axis = column_directions[hl.get_config("scrolling.direction")]
			local column = axis and axis[direction]
			if column then
				-- Column order remains available when the adjacent window is offscreen.
				hl.dispatch(column == "l" and previous or next_column)
				return
			end
		end
		hl.dispatch(swap)
	end
end

function B.monitor_move(direction)
	local move = hl.dsp.window.move({ monitor = direction, follow = true })
	local previous = hl.dsp.layout("swapcol l")
	local next_column = hl.dsp.layout("swapcol r")
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

		local axis = column_directions[hl.get_config("scrolling.direction")]
		local travel = axis and axis[direction]
		if not travel then
			return
		end

		local index = window.layout.column.index
		local swaps, swap = index, previous
		if travel == "l" then
			local last_index = index
			for _, other in ipairs(hl.get_workspace_windows(window.workspace)) do
				local layout = other.layout
				if not other.floating and layout.column then
					last_index = math.max(last_index, layout.column.index)
				end
			end
			swaps, swap = last_index - index, next_column
		end
		-- Enter the destination strip from the crossed monitor edge, rather than beside its focused column.
		for _ = 1, swaps do
			hl.dispatch(swap)
		end
	end
end

function B.column_width(width)
	local resize = hl.dsp.layout("colresize " .. width)
	local unmaximize = hl.dsp.window.fullscreen({ mode = "maximized", action = "unset", layout_aware = true })
	return function()
		if scrolling() then
			if hl.get_active_window().fullscreen == 1 then
				hl.dispatch(unmaximize)
			end
			hl.dispatch(resize)
		end
	end
end

function B.maximize()
	local maximize = hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle", layout_aware = true })
	return function()
		if not scrolling() or hl.get_active_window().fullscreen == 2 then
			hl.dispatch(maximize)
			return
		end

		local window = hl.get_active_window()
		local column = window.layout.column
		-- Maximized columns trigger fullscreen fades that break the continuous scrolling strip.
		local width = 1.0
		if window.fullscreen ~= 1 and column.width >= 1.0 then
			width = hl.get_config("scrolling.column_width")
		end
		B.column_width(width)()
	end
end

function B.layout(name, direction)
	return function()
		hl.config({ scrolling = { direction = direction }, general = { layout = name } })
	end
end

function B.workspace(number, move)
	return function()
		workspace.dispatch(number, move)
	end
end

function B.overview()
	-- gloview loads after the config registers its bindings.
	hl.dispatch(hl.plugin.gloview.toggle)
end

require("shared-binds")(B)
