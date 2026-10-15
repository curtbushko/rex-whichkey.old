-- A Rex-specific subset of which-key v3's spec format, shared by the terminal
-- frontend and Rex dispatcher. Pure Lua 5.1: no Neovim or terminal dependency.
local M = {}
local Tree = {}
Tree.__index = Tree
local fields = { desc = true, group = true, icon = true, cond = true, hidden = true, args = true, confirm = true }

local function evaluate(value)
	if type(value) == "function" then
		return value()
	end
	return value
end

local function tokens(lhs)
	assert(type(lhs) == "string" and lhs ~= "", "Mapping keys must be a non-empty string")
	local ret, i = {}, 1
	while i <= #lhs do
		local char, literal, label
		if lhs:sub(i, i) == "<" then
			local last = assert(lhs:find(">", i, true), "Unclosed key notation")
			local name = lhs:sub(i, last):lower()
			assert(name == "<space>" or name == "<lt>", "Unsupported terminal key notation: " .. name)
			char, literal, label = " ", "<Space>", "Space"
			if name == "<lt>" then
				char, literal, label = "<", "<lt>", "<"
			end
			i = last + 1
		else
			char = assert(lhs:sub(i):match("^([%z\1-\127\194-\244][\128-\191]*)"), "Invalid UTF-8 mapping key")
			assert(not char:find("%c"), "Escape, Backspace and Tab are reserved for navigation")
			literal, label = char, char
			if char == " " then
				literal, label = "<Space>", "Space"
			end
			i = i + #char
		end
		ret[#ret + 1] = { key = char, literal = literal, label = label }
	end
	return ret
end

local function attributes(parent, entry)
	local ret = {}
	for k, v in pairs(parent) do
		ret[k] = v
	end
	for k, v in pairs(entry) do
		if type(k) ~= "number" then
			assert(fields[k], "Unsupported Rex mapping option: " .. tostring(k))
			ret[k] = v
		end
	end
	return ret
end

function Tree:get(lhs)
	if lhs == "" then
		return self.root
	end
	local normalized = ""
	for _, token in ipairs(tokens(lhs)) do
		normalized = normalized .. token.literal
	end
	return self.nodes[normalized]
end

-- A data-only view for the helper: functions and action arguments never leave
-- Rex. Preorder preserves submenu ordering, including implicit prefix groups.
function Tree:snapshot(position)
	local entries = {}
	local function visit(node)
		for _, child in ipairs(node.children) do
			entries[#entries + 1] = {
				lhs = child.lhs,
				action = child.action ~= nil,
				desc = child.desc,
				group = child.is_group and (child.group or child.desc or child.label) or nil,
				icon = child.icon,
				confirm = child.confirm == true,
				hidden = child.hidden == true,
			}
			visit(child)
		end
	end
	visit(self.root)
	return {
		version = 1,
		title = self.root.desc,
		icon = self.root.icon,
		icons = self.icons,
		position = position,
		entries = entries,
	}
end

function M.config_from_snapshot(snapshot)
	assert(
		type(snapshot) == "table" and snapshot.version == 1 and type(snapshot.entries) == "table",
		"Invalid which-key menu snapshot"
	)
	local config = {
		title = snapshot.title,
		icon = snapshot.icon,
		icons = snapshot.icons,
		window = { position = snapshot.position },
		spec = {},
	}
	for _, record in ipairs(snapshot.entries) do
		assert(type(record) == "table" and type(record.action) == "boolean", "Invalid snapshot entry")
		local entry = {
			record.lhs,
			desc = record.desc,
			group = record.group,
			icon = record.icon,
			confirm = record.confirm,
			hidden = record.hidden,
		}
		if record.action then
			entry[2] = "whichkey_snapshot_action"
		end
		config.spec[#config.spec + 1] = entry
	end
	return config
end

function M.new(config)
	assert(type(config) == "table" and type(config.spec) == "table", "Expected a which-key-style config with spec")
	local root = { lhs = "", children = {}, lookup = {}, label = "", desc = config.title or "Rex", icon = config.icon }
	local self = setmetatable({ root = root, nodes = { [""] = root }, icons = config.icons or {} }, Tree)
	local function walk(entries, inherited)
		for _, entry in ipairs(entries) do
			assert(type(entry) == "table", "Each mapping or attribute scope must be a table")
			local attrs = attributes(inherited, entry)
			assert(
				attrs.cond == nil or type(attrs.cond) == "boolean" or type(attrs.cond) == "function",
				"Mapping cond must be boolean or function"
			)
			local enabled = attrs.cond == nil or evaluate(attrs.cond)
			if enabled then
				if type(entry[1]) ~= "string" then
					walk(entry, attrs)
				else
					local action = entry[2]
					assert(
						action == nil or type(action) == "string" or type(action) == "function",
						"Mapping action must be a Rex action name or function"
					)
					assert(not attrs.args or type(attrs.args) == "table", "Mapping args must be a table")
					assert(attrs.confirm == nil or type(attrs.confirm) == "boolean", "Mapping confirm must be boolean")
					assert(attrs.hidden == nil or type(attrs.hidden) == "boolean", "Mapping hidden must be boolean")
					local node = root
					for _, token in ipairs(tokens(entry[1])) do
						if not node.lookup[token.key] then
							local child = {
								key = token.key,
								label = token.label,
								lhs = node.lhs .. token.literal,
								parent = node,
								children = {},
								lookup = {},
							}
							node.lookup[token.key] = child
							node.children[#node.children + 1] = child
							self.nodes[child.lhs] = child
						end
						node = node.lookup[token.key]
					end
					assert(not (node.action and action), "Duplicate mapping action: " .. node.lhs)
					local desc, group, icon = evaluate(attrs.desc), evaluate(attrs.group), evaluate(attrs.icon)
					assert(desc == nil or type(desc) == "string", "Mapping desc must return a string")
					assert(group == nil or type(group) == "string", "Mapping group must return a string")
					assert(icon == nil or type(icon) == "string", "Mapping icon must return a glyph string")
					assert(not action or (desc and desc ~= ""), "Action mapping needs desc: " .. node.lhs)
					assert(not (action and group), "A mapping cannot be both an action and group")
					node.action = action or node.action
					node.desc, node.group, node.icon = desc or node.desc, group or node.group, icon or node.icon
					node.args, node.confirm, node.hidden = attrs.args, attrs.confirm == true, attrs.hidden == true
				end
			end
		end
	end
	walk(config.spec, {})
	for _, node in pairs(self.nodes) do
		assert(not (node.action and #node.children > 0), "Mapping cannot be both an action and submenu: " .. node.lhs)
		node.is_group = node == root or node.group ~= nil or #node.children > 0
	end
	return self
end

return M
