local M = {}

-- assign workspaces
local monitor_offsets = {
    ["DP-1"] = 0,
    ["DP-2"] = 10,
}

-- returns the workspace offset for the active monitor (dp-1: 0, dp-2: 10)
local function ws_offset()
    local ws = hl.get_active_workspace()
    if ws and ws.monitor then
        return monitor_offsets[ws.monitor.name] or 0
    end
    return 0
end

function M.bind_workspace(i)
    local key = tostring(i % 10)

    -- move to workspace
    hl.bind(Mod .. " + " .. key, function()
        hl.dispatch(hl.dsp.focus({ workspace = i + ws_offset() }))
    end)

    -- dont follow window move to workspace
    hl.bind(Mod .. " + SHIFT + " .. key, function()
        local ws = hl.get_active_workspace()
        local current = ws and ws.id or 1
        hl.dispatch(hl.dsp.window.move({ workspace = i + ws_offset() }))
        hl.dispatch(hl.dsp.focus({ workspace = current }))
    end)

    -- follow window move to workspace
    hl.bind(Mod .. " + CTRL + " .. key, function()
        local target = i + ws_offset()
        hl.dispatch(hl.dsp.window.move({ workspace = target }))
        hl.dispatch(hl.dsp.focus({ workspace = target }))
    end)
end

return M
