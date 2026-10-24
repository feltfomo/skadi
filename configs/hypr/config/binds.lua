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

function B.column_width(width)
	local resize = hl.dsp.layout("colresize " .. width)
	return function()
		if scrolling() then
			hl.dispatch(resize)
		end
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
