local bind = {}
-- groups provide diagnostic context while modifier state remains lexical
local groups = {}
local current_modifiers = ""

-- callers may use a finished chord string or a list of modifier parts
local function modifier_text(modifiers)
	if type(modifiers) == "table" then
		return table.concat(modifiers, " + ")
	end

	return modifiers or ""
end

local function merge_modifiers(left, right)
	left = modifier_text(left)
	right = modifier_text(right)

	if left == "" then
		return right
	end
	if right == "" then
		return left
	end

	return left .. " + " .. right
end

-- wrapped entries keep hyprland options next to their dispatcher
local function split_entry(entry)
	if type(entry) ~= "table" or entry.action == nil then
		return entry, nil
	end

	local options = {}
	for key, value in pairs(entry) do
		if key ~= "action" then
			options[key] = value
		end
	end

	return entry.action, options
end

local function register(modifiers, key, entry, explicit_options)
	assert(type(key) == "string", "bind key must be a string")

	local action, options = split_entry(entry)
	options = explicit_options or options
	assert(action ~= nil, "bind action is required")

	local chord = merge_modifiers(modifiers, key)
	if options and next(options) then
		hl.bind(chord, action, options)
	else
		hl.bind(chord, action)
	end
end

-- restore the outer scope even when config registration raises an error
local function with_modifiers(modifiers, define)
	local previous = current_modifiers
	current_modifiers = merge_modifiers(previous, modifiers)

	local ok, result = xpcall(define, debug.traceback)
	current_modifiers = previous
	if not ok then
		error(result, 0)
	end

	return result
end

-- two arguments inherit the current scope while three select explicit modifiers
setmetatable(bind, {
	__call = function(_, first, second, third, fourth)
		if type(second) == "string" then
			register(first, second, third, fourth)
			return
		end

		register(current_modifiers, first, second, third)
	end,
})

-- modifier scopes compose with defaults from their enclosing group
function bind.mods(modifiers, bindings)
	if type(bindings) == "function" then
		return with_modifiers(modifiers, bindings)
	end

	return with_modifiers(modifiers, function()
		for key, entry in pairs(bindings) do
			register(current_modifiers, key, entry)
		end
	end)
end

-- group names never change the generated chord
function bind.group(name, options, define)
	if type(options) == "function" then
		define = options
		options = {}
	end

	options = options or {}
	assert(type(name) == "string" and name ~= "", "bind group name is required")
	assert(type(define) == "function", "bind group body is required")

	table.insert(groups, name)
	local path = table.concat(groups, "/")
	local ok, result = xpcall(function()
		return with_modifiers(options.mods, define)
	end, debug.traceback)
	table.remove(groups)

	if not ok then
		error("bind group " .. path .. " failed\n" .. result, 0)
	end

	return result
end

return bind
