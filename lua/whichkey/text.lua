-- Terminal-cell replacements for Neovim's strdisplaywidth/strcharpart helpers.
local utf8 = require("lua-utf8")
local M = {}

function M.clean(value)
	return tostring(value):gsub("\27%[[0-?]*[ -/]*[@-~]", ""):gsub("%c", " ")
end

function M.width(value)
	return utf8.width(value)
end

function M.clip(value, width)
	local ret, used = {}, 0
	for char in value:gmatch(utf8.charpattern) do
		local size = M.width(char)
		if used + size > width then
			break
		end
		ret[#ret + 1], used = char, used + size
	end
	return table.concat(ret)
end

function M.fit(value, width, align, ellipsis)
	width = math.max(0, math.floor(width))
	if M.width(value) > width then
		ellipsis = ellipsis or "…"
		value = M.clip(value, math.max(0, width - M.width(ellipsis))) .. M.clip(ellipsis, width)
	end
	local padding = math.max(0, width - M.width(value))
	if align == "right" then
		return string.rep(" ", padding) .. value
	elseif align == "center" then
		return string.rep(" ", math.floor(padding / 2)) .. value .. string.rep(" ", math.ceil(padding / 2))
	end
	return value .. string.rep(" ", padding)
end

return M
