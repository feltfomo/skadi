local G = require("globals")

if G.hostname == "lumi" then
	hl.monitor({
		output = "eDP-1",
		mode = "1920x1080@60",
		position = "0x0",
		scale = "1",
	})
elseif G.hostname == "khion" then
	-- two side-by-side 1440p@180 panels: left at 0x0, right at 2560x0
	for i, output in ipairs({ G.monitors.left, G.monitors.right }) do
		hl.monitor({
			output = output,
			mode = "2560x1440@180",
			position = tostring((i - 1) * 2560) .. "x0",
			scale = "1",
		})
	end
end