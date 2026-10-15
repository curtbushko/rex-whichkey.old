-- Menu navigation and display data derived only from the shared mapping tree.
local M = {}

local function event(state, kind)
	return {
		kind = kind or "render",
		prefix = state.prefix or "",
		page = state.page or 0,
		confirmation = state.confirmation or "",
		lhs = "",
		confirmed = false,
	}
end

function M.step(tree, state, key, pages)
	local ret = event(state)
	local node = assert(tree:get(ret.prefix), "Unknown submenu prefix")
	if ret.confirmation ~= "" then
		if key == "y" then
			local mapping = assert(tree:get(ret.confirmation), "Unknown confirmation mapping")
			assert(mapping.action and mapping.confirm, "Mapping does not request confirmation")
			ret.kind, ret.lhs, ret.confirmed = "dispatch", mapping.lhs, true
		end
		ret.confirmation, ret.page = "", 0
		return ret
	end
	if key == "\27" or key == "\127" or key == "\b" then
		if node.parent then
			ret.prefix, ret.page = node.parent.lhs, 0
		else
			ret.kind = "quit"
		end
		return ret
	elseif key == "\t" then
		ret.page = (ret.page + 1) % math.max(1, pages or 1)
		return ret
	end
	local target = node.lookup[key]
	if target then
		if target.is_group then
			ret.prefix, ret.page = target.lhs, 0
		elseif target.action then
			if target.confirm then
				ret.confirmation, ret.page = target.lhs, 0
			else
				ret.kind, ret.lhs = "dispatch", target.lhs
			end
		end
	elseif key == "q" then
		ret.kind = "quit"
	end
	return ret
end

local function hidden(node)
	while node do
		if node.hidden then
			return true
		end
		node = node.parent
	end
	return false
end

local function icon(node)
	while node and node.parent do
		if node.icon then
			return node.icon
		end
		node = node.parent
	end
end

function M.display(tree, state, ascii)
	local node = assert(tree:get(state.prefix or ""), "Unknown submenu prefix")
	local data = { quit_with_q = node.lookup.q == nil }
	if state.confirmation and state.confirmation ~= "" then
		local mapping = assert(tree:get(state.confirmation), "Unknown confirmation mapping")
		data.title = "Confirm: " .. mapping.desc
		data[1], data[2] = { "y", mapping.desc, critical = true }, { "n", "Cancel" }
		return data
	elseif state.notice and state.notice ~= "" then
		data.title, data[1] = "Action failed", { "q", "Dismiss" }
		return data
	end
	local trail, parent = {}, node
	while parent and parent.parent do
		table.insert(trail, 1, parent.group or parent.desc or parent.label)
		parent = parent.parent
	end
	table.insert(trail, 1, tree.root.desc)
	if #trail == 1 then
		trail[#trail + 1] = "Which-key"
	end
	local breadcrumb = ascii and ">" or (tree.icons.breadcrumb or "»")
	data.title = table.concat(trail, " " .. breadcrumb .. " ")
	if not ascii and tree.root.icon then
		data.title = tree.root.icon .. " " .. data.title
	end
	for _, child in ipairs(node.children) do
		if not hidden(child) then
			local desc = child.group or child.desc or child.label
			if child.is_group then
				desc = desc .. " " .. (tree.icons.group or "+")
			end
			local glyph = not ascii and icon(child)
			if glyph then
				desc = glyph .. " " .. desc
			end
			data[#data + 1] = { child.label, desc, group = child.is_group, critical = child.confirm }
		end
	end
	return data
end

return M
