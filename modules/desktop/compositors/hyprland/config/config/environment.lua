local G = require("globals")

-- compositor-owned cursor settings keep wayland and xwayland clients consistent
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

-- khion is the nvidia host and does not use driver-managed vrr
if G.hostname == "khion" then
	hl.env("__GL_VRR_ALLOWED", "0")
end
