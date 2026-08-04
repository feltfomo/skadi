local G = require("globals")

-- app binds
hl.bind(G.mod .. " + T", hl.dsp.exec_cmd(G.terminal))
hl.bind(G.mod .. " + SPACE", hl.dsp.global("caelestia:launcher"))
hl.bind("Print", hl.dsp.exec_cmd(G.screenshot))

-- window binds
hl.bind(G.mod .. " + Q", hl.dsp.window.close())
hl.bind(G.mod .. " + V", hl.dsp.window.float())
hl.bind(G.mod .. " + F", hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }))
hl.bind(G.mod .. " + SHIFT + F", hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }))
hl.bind(G.mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })
hl.bind(G.mod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })

-- caelestia binds
hl.bind(G.mod .. " + C", hl.dsp.exec_cmd(G.clipboard))

-- focus / move windows (arrow keys + vim keys)
for dir, keys in pairs(G.directions) do
	hl.bind(G.mod .. " + " .. keys.arrow, hl.dsp.focus({ direction = dir }))
	hl.bind(G.mod .. " + " .. keys.vim, hl.dsp.focus({ direction = dir }))
	hl.bind(G.mod_alt .. " + " .. keys.arrow, hl.dsp.window.move({ direction = dir }))
	hl.bind(G.mod_alt .. " + " .. keys.vim, hl.dsp.window.move({ direction = dir }))
end

-- monitor focus binds
hl.bind(G.mod .. " + SHIFT + h", hl.dsp.focus({ monitor = G.monitors.left }))
hl.bind(G.mod .. " + SHIFT + l", hl.dsp.focus({ monitor = G.monitors.right }))

-- session menu
hl.bind(G.mod .. " + M", hl.dsp.global("caelestia:session"))

-- switch workspaces with mainMod + [0-9]
if G.hostname == "khion" then
	local workspace = require("helpers/workspace")
	for i = 1, 10 do
		workspace.bind_workspace(i)
	end
else
	for i = 1, 10 do
		local key = tostring(i % 10)
		hl.bind(G.mod .. " + " .. key, hl.dsp.focus({ workspace = i }))
		hl.bind(G.mod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
	end
end

-- layout switcher submap
hl.bind(G.mod .. " + SHIFT + L", hl.dsp.submap("layout"))

hl.define_submap("layout", function()
	local layouts = { d = "dwindle", m = "master", s = "scrolling", o = "monocle" }

	for key, layout in pairs(layouts) do
		hl.bind(key, function()
			hl.config({ general = { layout = layout } })
			hl.dispatch(hl.dsp.submap("reset"))
		end)
	end

	hl.bind("Escape", hl.dsp.submap("reset"))
end)
