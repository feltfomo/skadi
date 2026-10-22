local G = require("globals")

hl.bind(G.mod .. " + T", hl.dsp.exec_cmd(G.terminal))
-- the client avoids python startup overhead when talking to the running daemon
hl.bind(G.mod .. " + S", hl.dsp.exec_cmd("pypr-client toggle spotify"))
hl.bind(G.mod .. " + E", hl.dsp.exec_cmd("pypr-client toggle thunar"))
hl.bind(G.mod .. " + CTRL + F", hl.dsp.exec_cmd("pypr-client fetch_client_menu"))

hl.bind(G.mod .. " + SPACE", hl.dsp.global("quickshell:searchToggle"))
-- gloview loads at startup, after the config has registered its bindings
hl.bind(G.mod .. " + Tab", function()
	hl.dispatch(hl.plugin.gloview.toggle)
end)
hl.bind(G.mod .. " + N", hl.dsp.global("quickshell:sidebarRightToggle"))
hl.bind(G.mod .. " + M", hl.dsp.global("quickshell:sidebarRightToggle"))
hl.bind(G.mod .. " + C", hl.dsp.exec_cmd("end4-pc-shell-ipc search clipboardToggle"))
hl.bind(G.mod .. " + comma", hl.dsp.global("quickshell:settingsToggle"))
hl.bind(G.mod .. " + SHIFT + M", hl.dsp.global("quickshell:mediaControlsToggle"))
hl.bind(G.mod .. " + CTRL + L", hl.dsp.global("quickshell:lock"))
hl.bind(G.mod .. " + CTRL + T", hl.dsp.global("quickshell:wallpaperSelectorToggle"))

hl.bind("Print", hl.dsp.global("quickshell:regionScreenshot"))
hl.bind(G.mod .. " + SHIFT + S", hl.dsp.exec_cmd("hyprshot -m region --raw | satty --filename -"))

hl.bind("XF86MonBrightnessUp", hl.dsp.global("quickshell:brightnessIncrease"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.global("quickshell:brightnessDecrease"), { locked = true, repeating = true })
hl.bind(
	"XF86AudioRaiseVolume",
	hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 2%+"),
	{ locked = true, repeating = true }
)
hl.bind(
	"XF86AudioLowerVolume",
	hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%-"),
	{ locked = true, repeating = true }
)
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })

hl.bind(G.mod .. " + Q", hl.dsp.window.close())
hl.bind(G.mod .. " + V", hl.dsp.window.float())
hl.bind(G.mod .. " + F", hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }))
hl.bind(G.mod .. " + mouse:273", hl.dsp.window.resize())
hl.bind(G.mod .. " + mouse:272", hl.dsp.window.drag())
hl.bind(G.mod .. " + SHIFT + F", hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }))
hl.bind(G.mod .. " + SHIFT + h", hl.dsp.focus({ monitor = G.monitors.left }))
hl.bind(G.mod .. " + SHIFT + l", hl.dsp.focus({ monitor = G.monitors.right }))

for direction, keys in pairs(G.directions) do
	local focus = hl.dsp.focus({ direction = direction })
	hl.bind(G.mod .. " + " .. keys.arrow, focus)
	hl.bind(G.mod .. " + " .. keys.vim, focus)

	local move = hl.dsp.window.move({ direction = direction })
	hl.bind(G.mod_alt .. " + " .. keys.arrow, move)
	hl.bind(G.mod_alt .. " + " .. keys.vim, move)
end

if G.hostname == "khion" then
	local workspace = require("lib.workspace")
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

-- every layout choice resets the submap so normal binds resume immediately
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
