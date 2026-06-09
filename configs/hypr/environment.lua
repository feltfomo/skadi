-- common
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
-- nvidia only (HostName comes from globals.lua, which is loaded first)
if HostName == "khion" then
	hl.env("__GL_VRR_ALLOWED", "0")
end
