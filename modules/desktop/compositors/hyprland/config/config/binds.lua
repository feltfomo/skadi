-- hyprland-only shortcuts, one per line. a command string runs through exec; anything else is a
-- dispatcher, such as hl.dsp.window.pseudo(). shortcuts both compositors share belong in
-- modules/desktop/bindings/_binds.nix, which also catches a chord bound twice.
local binds = {
	-- { "SUPER + X", "kitty --class btop -e btop" },
	-- { "SUPER + Z", hl.dsp.window.pseudo() },
}

for _, bind in ipairs(binds) do
	local chord, action, options = bind[1], bind[2], bind[3]
	if type(action) == "string" then
		action = hl.dsp.exec_cmd(action)
	end
	if options then
		hl.bind(chord, action, options)
	else
		hl.bind(chord, action)
	end
end

-- the shared shortcuts from _binds.nix, with the runtime helpers they call.
require("shared-binds")(require("lib.binds"))
