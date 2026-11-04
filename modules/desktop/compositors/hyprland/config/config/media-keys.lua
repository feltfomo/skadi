local G = require("globals")

-- lumi's laptop keyboard has fn media keys; khion's wooting has none, and lumi's firmware handles brightness itself
if G.hostname ~= "lumi" then
	return
end

-- media keys keep working on the lock screen, and volume repeats while held
local held = { locked = true, repeating = true }
local locked = { locked = true }

local keys = {
	{ "XF86AudioRaiseVolume", "noctalia msg volume-up", held },
	{ "XF86AudioLowerVolume", "noctalia msg volume-down", held },
	{ "XF86AudioMute", "noctalia msg volume-mute", locked },
	{ "XF86AudioPlay", "noctalia msg media toggle", locked },
	{ "XF86AudioNext", "noctalia msg media next", locked },
	{ "XF86AudioPrev", "noctalia msg media previous", locked },
}

for _, key in ipairs(keys) do
	hl.bind(key[1], hl.dsp.exec_cmd(key[2]), key[3])
end
