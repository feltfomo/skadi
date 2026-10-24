local source, generated, host = arg[1], arg[2], arg[3] or "khion"
package.path = source .. "/configs/hypr/?.lua;" .. package.path
package.loaded.globals = { hostname = "khion", monitors = { left = "DP-1", right = "DP-2" } }
package.preload["shared-binds"] = function()
	return dofile(generated)
end

local bindings, rules = {}, {}
local current = { tiled_layout = "scrolling" }
local window = { floating = false }
local monitor = { name = "DP-2" }
local last, configuration
local function action(name)
	return function(options)
		return function()
			last = { name = name, options = options }
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
	workspace_rule = function(rule)
		table.insert(rules, rule)
	end,
	config = function(value)
		configuration = value
	end,
	dispatch = function(callback)
		callback()
	end,
	plugin = { gloview = {
		toggle = function()
			last = { name = "overview" }
		end,
	} },
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
assert(last.name == "fullscreen" and last.options.layout_aware and last.options.mode == "maximized")
bindings["super + right"]()
assert(last.name == "layout" and last.options == "focus r")
bindings["super + shift + f"]()
assert(last.name == "fullscreen" and last.options.layout_aware and last.options.mode == "fullscreen")
bindings["super + alt + f"]()
assert(last.name == "layout" and last.options == "colresize 1.0")
bindings["super + alt + d"]()
assert(last.options == "colresize 0.5")
bindings["super + alt + h"]()
assert(last.name == "swap" and last.options.direction == "left")
bindings["super + ctrl + h"]()
assert(last.name == "focus" and last.options.monitor == "left")
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
bindings["super + h"]()
assert(last.name == "focus" and last.options.direction == "left")
local before = last
bindings["super + alt + f"]()
assert(last == before)
current.tiled_layout = "scrolling"
window.floating = true
bindings["super + h"]()
assert(last.name == "focus")
window = nil
bindings["super + h"]()
assert(last.name == "focus")
bindings["super + tab"]()
assert(last.name == "overview")
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
