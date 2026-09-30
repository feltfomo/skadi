return function(action, target)
	return hl.dsp.exec_cmd("serpantinum msg " .. action .. " " .. target)
end
