return function(target, action)
	return hl.dsp.exec_cmd("lucid-shell-ipc " .. target .. " " .. action)
end
