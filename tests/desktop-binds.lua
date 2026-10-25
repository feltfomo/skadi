local source, generated, host = arg[1], arg[2], arg[3] or "khion"
package.path = source .. "/configs/hypr/?.lua;" .. package.path
package.loaded.globals = { hostname = "khion", monitors = { left = "DP-1", right = "DP-2" } }
package.preload["shared-binds"] = function()
	return dofile(generated)
end

local bindings, rules = {}, {}
local current = { tiled_layout = "scrolling" }
local window = { floating = false, fullscreen = 0, layout = { column = { width = 0.5 } } }
local monitor = { name = "DP-2" }
local last, configuration
local calls = {}
local scroll_direction = "right"
local on_move, destination_windows
local function action(name)
	return function(options)
		return function()
			last = { name = name, options = options }
			table.insert(calls, last)
			if name == "move" and on_move then
				on_move(options)
			end
		end
	end
end

hl = {
	dsp = {
		window = {
			fullscreen = action("fullscreen"),
			resize = action("resize"),
			close = action("close"),
			float = action("float"),
			drag = action("drag"),
			swap = action("swap"),
			move = action("move"),
		},
		exec_cmd = action("exec"),
		layout = action("layout"),
		focus = action("focus"),
		exit = action("exit"),
	},
	get_active_workspace = function()
		return current
	end,
	get_active_monitor = function()
		return monitor
	end,
	get_active_window = function()
		return window
	end,
	get_workspace_windows = function()
		return destination_windows
	end,
	get_config = function(key)
		if key == "scrolling.column_width" then
			return 0.5
		end
		assert(key == "scrolling.direction")
		return scroll_direction
	end,
	workspace_rule = function(rule)
		table.insert(rules, rule)
	end,
	config = function(value)
		configuration = value
	end,
	dispatch = function(callback)
		callback()
	end,
	bind = function(chord, callback)
		chord = chord:lower()
		assert(not bindings[chord], "duplicate chord: " .. chord)
		bindings[chord] = callback
	end,
}

dofile(source .. "/configs/hypr/config/binds.lua")
assert(#rules == (host == "khion" and 20 or 0))
bindings["super + h"]()
assert(last.name == "layout" and last.options == "focus l")
bindings["super + f"]()
assert(last.name == "layout" and last.options == "colresize 1.0")
window.layout.column.width = 1.0
bindings["super + f"]()
assert(last.name == "layout" and last.options == "colresize 0.5")
window.fullscreen = 1
bindings["super + f"]()
assert(last.name == "layout" and last.options == "colresize 1.0")
assert(calls[#calls - 1].name == "fullscreen" and calls[#calls - 1].options.action == "unset")
bindings["super + alt + d"]()
assert(last.name == "layout" and last.options == "colresize 0.5")
assert(calls[#calls - 1].name == "fullscreen" and calls[#calls - 1].options.action == "unset")
window.fullscreen = 0
window.layout.column.width = 0.5
window.fullscreen = 2
bindings["super + f"]()
assert(last.name == "fullscreen" and last.options.mode == "maximized")
window.fullscreen = 0
bindings["super + right"]()
assert(last.name == "layout" and last.options == "focus r")
bindings["super + shift + f"]()
assert(last.name == "fullscreen" and last.options.layout_aware and last.options.mode == "fullscreen")
bindings["super + alt + f"]()
assert(last.name == "layout" and last.options == "colresize 1.0")
bindings["super + alt + d"]()
assert(last.options == "colresize 0.5")
bindings["super + alt + h"]()
assert(last.name == "layout" and last.options == "swapcol l")
for axis, directions in pairs({
	right = { h = "l", l = "r", k = "up", j = "down" },
	left = { h = "r", l = "l", k = "up", j = "down" },
	down = { k = "l", j = "r", h = "left", l = "right" },
	up = { k = "r", j = "l", h = "left", l = "right" },
}) do
	scroll_direction = axis
	for key, direction in pairs(directions) do
		bindings["super + alt + " .. key]()
		if direction == "l" or direction == "r" then
			assert(last.name == "layout" and last.options == "swapcol " .. direction)
		else
			assert(last.name == "swap" and last.options.direction == direction)
		end
	end
end
scroll_direction = "right"
bindings["super + ctrl + h"]()
assert(last.name == "focus" and last.options.monitor == "left")
for key, direction in pairs({
	h = "left",
	Left = "left",
	l = "right",
	Right = "right",
	k = "up",
	Up = "up",
	j = "down",
	Down = "down",
}) do
	bindings[("super + shift + alt + " .. key):lower()]()
	assert(last.name == "move" and last.options.monitor == direction and last.options.follow == true)
end
local saved_window = window
for _, case in ipairs({
	{ axis = "right", key = "l", index = 2, swap = "l", count = 2, width = 1.0 },
	{ axis = "right", key = "h", index = 0, swap = "r", count = 2 },
	{ axis = "left", key = "l", index = 0, swap = "r", count = 2 },
	{ axis = "down", key = "j", index = 2, swap = "l", count = 2, width = 0.667 },
	{ axis = "right", key = "l", index = 0, count = 0 },
	{ axis = "right", key = "l", index = 2, count = 0, same_monitor = true },
	{ axis = "right", key = "l", index = 2, count = 0, floating = true },
	{ axis = "right", key = "l", index = 2, count = 0, layout = "dwindle" },
	{ axis = "down", key = "l", index = 2, count = 0 },
	{ axis = "right", key = "l", index = 0, count = 0, fullscreen = 2 },
}) do
	scroll_direction = case.axis
	window = {
		monitor = { name = "source" },
		floating = case.floating or false,
		fullscreen = case.fullscreen or 0,
		layout = { column = { width = case.width or 0.5 } },
	}
	on_move = function()
		window.monitor = { name = case.same_monitor and "source" or "destination" }
		window.workspace = { tiled_layout = case.layout or "scrolling" }
		window.layout = { column = { index = case.index } }
	end
	destination_windows = {
		{ floating = false, layout = { column = { index = 0 } } },
		{ floating = false, layout = { column = { index = 1 } } },
		{ floating = false, layout = { column = { index = 2 } } },
		{ floating = true, layout = {} },
	}
	local before_calls = #calls
	bindings["super + shift + alt + " .. case.key]()
	local resized = not case.same_monitor and not case.floating and not case.layout and case.fullscreen ~= 2
	assert(#calls == before_calls + 1 + case.count + (resized and 1 or 0))
	if resized then
		assert(calls[before_calls + 2].name == "layout")
		assert(calls[before_calls + 2].options == "colresize " .. (case.width or 0.5))
	end
	for index = before_calls + (resized and 3 or 2), #calls do
		assert(calls[index].name == "layout" and calls[index].options == "swapcol " .. case.swap)
	end
end
window, on_move, scroll_direction = saved_window, nil, "right"
for chord, command in pairs({
	["super + s"] = "pypr-client toggle spotify",
	["super + e"] = "pypr-client toggle thunar",
	["super + comma"] = "pypr-client toggle settings",
	["super + shift + comma"] = "noctalia msg volume-down",
	["super + shift + minus"] = "noctalia msg volume-down",
	["super + shift + period"] = "noctalia msg volume-up",
	["super + shift + equal"] = "noctalia msg volume-up",
}) do
	bindings[chord]()
	assert(last.name == "exec" and last.options == command)
end
bindings["super + 9"]()
assert(last.name == "focus" and last.options.workspace == (host == "khion" and 19 or 9))
bindings["super + shift + 1"]()
assert(last.name == "move" and last.options.workspace == (host == "khion" and 11 or 1) and last.options.follow == false)
monitor.name = "DP-1"
bindings["super + 1"]()
assert(last.options.workspace == 1)
bindings["super + 0"]()
assert(last.options.workspace == 10)
monitor.name = "DP-2"
bindings["super + shift + 0"]()
assert(last.options.workspace == (host == "khion" and 20 or 10) and last.options.follow == false)
bindings["super + ctrl + v"]()
assert(configuration.general.layout == "scrolling" and configuration.scrolling.direction == "down")
bindings["super + ctrl + s"]()
assert(configuration.scrolling.direction == "right")
current.tiled_layout = "dwindle"
bindings["super + f"]()
assert(last.name == "fullscreen" and last.options.layout_aware and last.options.mode == "maximized")
bindings["super + alt + h"]()
assert(last.name == "swap" and last.options.direction == "left")
bindings["super + h"]()
assert(last.name == "focus" and last.options.direction == "left")
local before = last
bindings["super + alt + f"]()
assert(last == before)
current.tiled_layout = "scrolling"
window.floating = true
bindings["super + f"]()
assert(last.name == "fullscreen" and last.options.mode == "maximized")
bindings["super + alt + h"]()
assert(last.name == "swap" and last.options.direction == "left")
bindings["super + h"]()
assert(last.name == "focus")
window = nil
bindings["super + alt + h"]()
assert(last.name == "swap" and last.options.direction == "left")
bindings["super + h"]()
assert(last.name == "focus")
assert(bindings["super + tab"] == nil)
bindings["super + m"]()
assert(last.name == "exit")
monitor = nil
bindings["super + 9"]()
assert(last.options.workspace == 9)
local workspace = require("lib.workspace")
workspace.configure({ first = 21, count = 10, banks = {}, selectBank = "global", moveFollows = true })
workspace.dispatch(10, true)
assert(last.name == "move" and last.options.workspace == 30 and last.options.follow == true)
print("desktop bindings passed")
