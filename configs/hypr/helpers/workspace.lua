local M = {}

local monitor_offsets = {
    ["DP-1"] = 0,
    ["DP-2"] = 10,
}

local function ws_offset()
    local mon = hl.get_active_monitor()
    return mon and (monitor_offsets[mon.name] or 0) or 0
end

function M.bind_workspace(i)
    local key = tostring(i % 10) -- i=10 -> "0", i=1 -> "1", etc.

    -- focus workspace i on active monitor
    hl.bind(Mod .. " + " .. key, function()
        hl.dispatch(hl.dsp.focus({ workspace = i + ws_offset() }))
    end)

    -- move window to workspace, don't follow
    hl.bind(Mod .. " + SHIFT + " .. key, function()
        local offset = ws_offset()
        local ws = hl.get_active_workspace()
        if not ws then return end
        local current = ws.id
        hl.dispatch(hl.dsp.window.move({ workspace = i + offset }))
        hl.dispatch(hl.dsp.focus({ workspace = current }))
    end)

    -- move window to workspace and follow
    hl.bind(Mod .. " + CTRL + " .. key, function()
        local target = i + ws_offset()
        hl.dispatch(hl.dsp.window.move({ workspace = target }))
        hl.dispatch(hl.dsp.focus({ workspace = target }))
    end)
end

return M
