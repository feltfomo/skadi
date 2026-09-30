-- RPC notifications let busy editors apply the palette when they can service it.
-- Matugen must never wait for an editor before finishing the other app themes.
local failures = {}
for _, address in ipairs(vim.fn.glob("$XDG_RUNTIME_DIR/nvim.*.0", false, true)) do
	local ok, channel = pcall(vim.fn.sockconnect, "pipe", address, { rpc = true })
	if ok and channel > 0 then
		local sent, err = pcall(
			vim.rpcnotify,
			channel,
			"nvim_exec_lua",
			"vim.schedule(function() vim.cmd.colorscheme('reactive') end)",
			{}
		)
		vim.fn.chanclose(channel)
		if not sent then
			table.insert(failures, address .. ": " .. tostring(err))
		end
	else
		table.insert(failures, address .. ": " .. tostring(channel))
	end
end
if #failures > 0 then
	error(table.concat(failures, "\n"))
end
