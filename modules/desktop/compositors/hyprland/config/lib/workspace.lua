local M = {}
local routing
local banks = {}
-- workspace rules can't be read back from lua, so the selected scroll axes are kept here
local scroll_directions = {}

function M.configure(policy)
	routing = policy
	for _, bank in ipairs(policy.banks) do
		banks[bank.output] = bank
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

local function active_bank()
	local monitor = hl.get_active_monitor()
	return monitor and banks[monitor.name] or routing
end

function M.step(direction)
	return function()
		local bank = active_bank()
		local target = hl.get_active_workspace().id + (direction == "up" and -1 or 1)
		-- stops at the bank's ends so it can't land on another monitor's workspaces
		if target >= bank.first and target < bank.first + bank.count then
			hl.dispatch(hl.dsp.focus({ workspace = target }))
		end
	end
end

function M.dispatch(slot, mode)
	return function()
		local target = active_bank().first + slot - 1
		if mode == "select" then
			hl.dispatch(hl.dsp.focus({ workspace = target }))
		else
			hl.dispatch(hl.dsp.window.move({ workspace = target, follow = mode == "follow" }))
		end
	end
end

return M
