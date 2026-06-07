local M = {}

local SPOTIFY_CLASS = "spotify"
local SPOTIFY_WS = "special:spotify"

hl.workspace_rule({
	workspace = SPOTIFY_WS,
	layout_opts = { specialScaleFactor = 0.6 },
})

local function find_spotify()
	local wins = hl.get_windows({ class = SPOTIFY_CLASS })
	return wins and wins[1] or nil
end

function M.toggle_spotify()
	local win = find_spotify()
	if not win then
		return
	end

	local ws = win.workspace
	if ws and ws.name == SPOTIFY_WS then
		hl.dispatch(hl.dsp.workspace.toggle_special("spotify"))
	else
		hl.dispatch(hl.dsp.window.move({ workspace = SPOTIFY_WS, window = win }))
	end
end

return M
