-- return a dispatcher so hyprland runs the ipc command only when the bind fires
return function(target, action)
	return hl.dsp.exec_cmd("end4-pc-shell-ipc " .. target .. " " .. action)
end
