local G = require("globals")

-- common
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

-- nvidia only
if G.hostname == "khion" then
	hl.env("__GL_VRR_ALLOWED", "0")
end