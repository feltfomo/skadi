local G = require("globals")

local ii_ipc_call = "$HOME/Projects/illogical-impulse-shell-nix/result/bin/illogical-impulse-shell-ipc"

local function ii_ipc(target, action)
	return hl.dsp.exec_cmd(ii_ipc_call .. " " .. target .. " " .. action)
end

hl.bind(G.mod .. " + T", hl.dsp.exec_cmd(G.terminal))
hl.bind(G.mod .. " + SPACE", ii_ipc("search", "toggle"))
hl.bind("Print", hl.dsp.exec_cmd(G.screenshot))

hl.bind(G.mod .. " + Tab", ii_ipc("search", "workspacesToggle"))
hl.bind(G.mod .. " + SHIFT + V", ii_ipc("search", "clipboardToggle"))
hl.bind(G.mod .. " + A", ii_ipc("sidebarLeft", "toggle"))
hl.bind(G.mod .. " + N", ii_ipc("sidebarRight", "toggle"))
hl.bind(G.mod .. " + Slash", ii_ipc("cheatsheet", "toggle"))
hl.bind(G.mod .. " + K", ii_ipc("osk", "toggle"))
hl.bind(G.mod .. " + SHIFT + M", ii_ipc("mediaControls", "toggle"))
hl.bind(G.mod .. " + G", ii_ipc("overlay", "toggle"))
hl.bind(G.mod .. " + J", ii_ipc("bar", "toggle"))
hl.bind(G.mod .. " + M", ii_ipc("session", "toggle"))
hl.bind("CTRL + ALT + Delete", ii_ipc("session", "toggle"))
hl.bind(G.mod .. " + CTRL + L", ii_ipc("lock", "activate"))
hl.bind(G.mod .. " + CTRL + T", ii_ipc("wallpaperSelector", "toggle"))
hl.bind(G.mod .. " + CTRL + P", ii_ipc("panelFamily", "cycle"))

hl.bind(G.mod .. " + SHIFT + S", ii_ipc("region", "screenshot"))
hl.bind(G.mod .. " + SHIFT + A", ii_ipc("region", "search"))
hl.bind(G.mod .. " + SHIFT + X", ii_ipc("region", "ocr"))
hl.bind(G.mod .. " + SHIFT + T", ii_ipc("screenTranslator", "translate"))
hl.bind(G.mod .. " + SHIFT + R", ii_ipc("region", "record"))
hl.bind(G.mod .. " + ALT + R", ii_ipc("region", "recordWithSound"))

hl.bind("XF86MonBrightnessUp", ii_ipc("brightness", "increment"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", ii_ipc("brightness", "decrement"), { locked = true, repeating = true })
hl.bind("XF86AudioPlay", ii_ipc("mpris", "playPause"), { locked = true })
hl.bind("XF86AudioPause", ii_ipc("mpris", "playPause"), { locked = true })
hl.bind("XF86AudioNext", ii_ipc("mpris", "next"), { locked = true })
hl.bind("XF86AudioPrev", ii_ipc("mpris", "previous"), { locked = true })

hl.bind(G.mod .. " + C", hl.dsp.exec_cmd(G.clipboard))

hl.bind(G.mod .. " + Q", hl.dsp.window.close())
hl.bind(G.mod .. " + V", hl.dsp.window.float())
hl.bind(G.mod .. " + F", hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }))
hl.bind(G.mod .. " + SHIFT + F", hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }))
hl.bind(G.mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })
hl.bind(G.mod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })

for dir, keys in pairs(G.directions) do
	hl.bind(G.mod .. " + " .. keys.arrow, hl.dsp.focus({ direction = dir }))
	hl.bind(G.mod .. " + " .. keys.vim, hl.dsp.focus({ direction = dir }))
	hl.bind(G.mod_alt .. " + " .. keys.arrow, hl.dsp.window.move({ direction = dir }))
	hl.bind(G.mod_alt .. " + " .. keys.vim, hl.dsp.window.move({ direction = dir }))
end

hl.bind(G.mod .. " + SHIFT + h", hl.dsp.focus({ monitor = G.monitors.left }))
hl.bind(G.mod .. " + SHIFT + l", hl.dsp.focus({ monitor = G.monitors.right }))

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
