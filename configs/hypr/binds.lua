local G = require("globals")

-- App Binds
hl.bind(G.mod .. " + T", hl.dsp.exec_cmd(G.terminal))
hl.bind(G.mod .. " + SPACE", hl.dsp.exec_cmd(G.noctalia_launcher))
hl.bind("Print", hl.dsp.exec_cmd(G.screenshot))

-- Window Binds
hl.bind(G.mod .. " + Q", hl.dsp.window.close())
hl.bind(G.mod .. " + V", hl.dsp.window.float())
hl.bind(G.mod .. " + F", hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }))
hl.bind(G.mod .. " + SHIFT + F", hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }))
hl.bind(G.mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })
hl.bind(G.mod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })

-- Noctalia Binds
hl.bind(G.mod .. " + C", hl.dsp.exec_cmd(G.noctalia_clipper))

-- Focus / move windows (arrow keys + vim keys)
for dir, keys in pairs(G.directions) do
	hl.bind(G.mod .. " + " .. keys.arrow, hl.dsp.focus({ direction = dir }))
	hl.bind(G.mod .. " + " .. keys.vim, hl.dsp.focus({ direction = dir }))
	hl.bind(G.mod_alt .. " + " .. keys.arrow, hl.dsp.window.move({ direction = dir }))
	hl.bind(G.mod_alt .. " + " .. keys.vim, hl.dsp.window.move({ direction = dir }))
end

-- Monitor Focus Binds
hl.bind(G.mod .. " + SHIFT + h", hl.dsp.focus({ monitor = G.monitors.left }))
hl.bind(G.mod .. " + SHIFT + l", hl.dsp.focus({ monitor = G.monitors.right }))

-- Log Out Bind
hl.bind(
	G.mod .. " + M",
	hl.dsp.exec_cmd("command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch exit")
)

-- Switch workspaces with mainMod + [0-9]
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

-- Layout switcher submap
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