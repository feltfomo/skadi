local M = {}
local routing
-- workspace rules can't be read back from lua, so the selected scroll axes are kept here
local scroll_directions = {}

function M.configure(policy)
	routing = policy
	for _, bank in ipairs(policy.banks) do
		for slot = 1, bank.count do
			hl.workspace_rule({ workspace = tostring(bank.first + slot - 1), monitor = bank.output, persistent = true })
		end
	end

	-- slot 1 scrolls on every monitor, the rest inherit general.layout
	for _, bank in ipairs(#policy.banks > 0 and policy.banks or { policy }) do
		hl.workspace_rule({ workspace = tostring(bank.first), layout = "scrolling" })
	end
end

function M.select_layout(workspace, name, direction)
	scroll_directions[workspace.id] = direction
	hl.workspace_rule({
		workspace = tostring(workspace.id),
		layout = name,
		layout_opts = { direction = direction },
	})
end

function M.scroll_direction(workspace)
	return scroll_directions[workspace.id] or hl.get_config("scrolling.direction")
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
