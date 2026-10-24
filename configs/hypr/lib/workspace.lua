local M = {}
local routing

function M.configure(policy)
	routing = policy
	for _, bank in ipairs(policy.banks) do
		for slot = 1, bank.count do
			hl.workspace_rule({ workspace = tostring(bank.first + slot - 1), monitor = bank.output, persistent = true })
		end
	end
end

function M.dispatch(slot, move)
	local first = routing.first
	if routing.selectBank == "focused-output" then
		local monitor = hl.get_active_monitor()
		for _, bank in ipairs(routing.banks) do
			if monitor and monitor.name == bank.output then
				first = bank.first
				break
			end
		end
	end

	local target = first + slot - 1
	if move then
		hl.dispatch(hl.dsp.window.move({ workspace = target, follow = routing.moveFollows }))
	else
		hl.dispatch(hl.dsp.focus({ workspace = target }))
	end
end

return M
