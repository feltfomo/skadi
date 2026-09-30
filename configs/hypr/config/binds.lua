local G = require("globals")
local bind = require("lib.bind")
local shell = require("lib.lucid")

-- groups organize the file and add useful context when registration fails
-- inherited modifiers keep common chords short while explicit binds remain available
bind.group("apps", { mods = G.mod }, function()
	bind("T", hl.dsp.exec_cmd(G.terminal))

	-- the client avoids python startup overhead when talking to the running daemon
	bind("S", hl.dsp.exec_cmd("pypr-client toggle spotify"))
	bind("E", hl.dsp.exec_cmd("pypr-client toggle thunar"))

	bind.mods("CTRL", {
		F = hl.dsp.exec_cmd("pypr-client fetch_client_menu"),
	})
end)

bind.group("shell", { mods = G.mod }, function()
	bind("SPACE", shell("launcher", "toggle"))
	-- gloview replaces the shell overview on the familiar workspace chord
	bind("Tab", hl.plugin.gloview.toggle)
	bind("N", shell("notifs", "toggle"))
	bind("K", shell("keyboard", "toggle"))
	bind("M", shell("launcher", "power"))
	bind("C", shell("launcher", "clipboard"))
	bind("comma", shell("settings", "toggle"))

	bind.mods("SHIFT", {
		M = shell("media", "toggle"),
	})

	bind.mods("CTRL", {
		L = shell("lock", "lock"),
		T = shell("launcher", "wallpaper"),
	})
end)

bind.group("capture", function()
	bind("Print", hl.dsp.exec_cmd(G.screenshot))

	bind.mods({ G.mod, "SHIFT" }, {
		S = shell("snap", "open"),
		X = shell("snap", "text"),
	})
end)

bind.group("media", function()
	-- wrapped actions keep hyprland bind flags beside the dispatcher they affect
	bind.mods("", {
		XF86MonBrightnessUp = {
			action = hl.dsp.exec_cmd("brightnessctl set +5%"),
			locked = true,
			repeating = true,
		},
		XF86MonBrightnessDown = {
			action = hl.dsp.exec_cmd("brightnessctl set 5%-"),
			locked = true,
			repeating = true,
		},
		XF86AudioPlay = { action = shell("media", "playPause"), locked = true },
		XF86AudioPause = { action = shell("media", "playPause"), locked = true },
		XF86AudioNext = { action = shell("media", "next"), locked = true },
		XF86AudioPrev = { action = shell("media", "previous"), locked = true },
	})
end)

bind.group("windows", { mods = G.mod }, function()
	bind("Q", hl.dsp.window.close())
	bind("V", hl.dsp.window.float())
	bind("F", hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }))
	bind("mouse:273", { action = hl.dsp.window.resize(), mouse = true })
	bind("mouse:272", { action = hl.dsp.window.drag(), mouse = true })

	bind.mods("SHIFT", {
		F = hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }),
		h = hl.dsp.focus({ monitor = G.monitors.left }),
		l = hl.dsp.focus({ monitor = G.monitors.right }),
	})

	-- both vim and arrow keys cause sometimes i feel like using arrows
	for direction, keys in pairs(G.directions) do
		local focus = hl.dsp.focus({ direction = direction })
		bind(keys.arrow, focus)
		bind(keys.vim, focus)

		local move = hl.dsp.window.move({ direction = direction })
		bind(G.mod_alt, keys.arrow, move)
		bind(G.mod_alt, keys.vim, move)
	end
end)

bind.group("workspaces", function()
	if G.hostname == "khion" then
		local workspace = require("lib.workspace")
		for i = 1, 10 do
			workspace.bind_workspace(i)
		end
		return
	end

	for i = 1, 10 do
		local key = tostring(i % 10)
		bind(G.mod, key, hl.dsp.focus({ workspace = i }))
		bind(G.mod .. " + SHIFT", key, hl.dsp.window.move({ workspace = i }))
	end
end)

bind.group("layout", { mods = { G.mod, "SHIFT" } }, function()
	bind("L", hl.dsp.submap("layout"))
end)

-- every layout choice resets the submap so normal binds resume immediately
hl.define_submap("layout", function()
	local layouts = { d = "dwindle", m = "master", s = "scrolling", o = "monocle" }

	for key, layout in pairs(layouts) do
		bind("", key, function()
			hl.config({ general = { layout = layout } })
			hl.dispatch(hl.dsp.submap("reset"))
		end)
	end

	bind("", "Escape", hl.dsp.submap("reset"))
end)
