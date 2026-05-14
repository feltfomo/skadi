-- App Binds
hl.bind(Mod .. " + T", hl.dsp.exec_cmd(Terminal))
hl.bind(Mod .. " + SPACE", hl.dsp.exec_cmd(Menu))
hl.bind("Print", hl.dsp.exec_cmd(ScreenShot))

-- Window Binds
hl.bind(Mod .. " + Q", hl.dsp.window.close())
hl.bind(Mod .. " + V", hl.dsp.window.float())
hl.bind(Mod .. " + F", hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle", }))
hl.bind(Mod .. " + SHIFT + F", hl.dsp.window.fullscreen({ "fullscreen", "toggle", }))
hl.bind(Mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })
hl.bind(Mod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })

for dir, keys in pairs(Directions) do
    -- focus
    hl.bind(Mod .. " + " .. keys.arrow, hl.dsp.focus({ direction = dir }))
    hl.bind(Mod .. " + " .. keys.vim, hl.dsp.focus({ direction = dir }))
    -- move
    hl.bind(ModAlt .. " + " .. keys.arrow, hl.dsp.window.move({ direction = dir }))
    hl.bind(ModAlt .. " + " .. keys.vim, hl.dsp.window.move({ direction = dir }))
end

-- Monitor Focus Binds
hl.bind(Mod .. " + SHIFT + h", hl.dsp.focus({ monitor = "DP-1" }))
hl.bind(Mod .. " + SHIFT + l", hl.dsp.focus({ monitor = "DP-2" }))

-- Log Out Bind
hl.bind(Mod .. " + M",
    hl.dsp.exec_cmd("command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch 'hl.dsp.exit()'"))

-- Switch workspaces with mainMod + [0-9]
if HostName == "khion" then
    local workspace = require("helpers/workspace")
    for i = 1, 10 do workspace.bind_workspace(i) end
else
    for i = 1, 10 do
        local key = tostring(i % 10)
        hl.bind(Mod .. " + " .. key, hl.dsp.focus({ workspace = i }))
        hl.bind(Mod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
    end
end

-- layout switcher submap
hl.bind(Mod .. " + SHIFT + L", hl.dsp.submap("layout"))

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
