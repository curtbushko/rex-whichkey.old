-- Adapted from folke/which-key.nvim, lua/which-key/layout.lua (Apache-2.0).
-- Upstream revision: 3aab2147e74890957785941f0c1ad87d0a44c15a
-- Changes: replace vim.* and plugin configuration with terminal text helpers;
-- bound truncation to display cells, including zero-width and wide characters.
local Text = require("text")
local M = {}

function M.dim(size, parent, ...)
	size = math.abs(size) < 1 and parent * size or size
	size = size < 0 and parent + size or size
	for _, dim in ipairs({ ... }) do
		if type(dim) == "number" then
			size = M.dim(dim, parent)
		else
			local min = dim.min and M.dim(dim.min, parent) or 0
			local max = dim.max and M.dim(dim.max, parent) or parent
			size = math.max(min, math.min(max, size))
		end
	end
	return math.floor(math.max(0, math.min(parent, size)) + 0.5)
end

local Table = {}
Table.__index = Table

function Table.new(opts)
	return setmetatable({ cols = opts.cols, rows = opts.rows, ellipsis = opts.ellipsis or "…" }, Table)
end

function Table:cells(opts)
	opts = opts or {}
	local spacing = opts.spacing or 1
	local widths, cells, total = {}, {}, 0
	for c, col in ipairs(self.cols) do
		widths[c] = 0
		local all_ws = true
		for r, row in ipairs(self.rows) do
			cells[r] = cells[r] or {}
			local value = Text.clean(row[col.key] or col.default or ""):gsub("%s*$", "")
			if value:find("%S") then
				all_ws = false
			end
			if col.padding then
				value = string.rep(" ", col.padding[1] or 0) .. value .. string.rep(" ", col.padding[2] or 0)
			end
			if c ~= #self.cols then
				value = value .. string.rep(" ", spacing)
			end
			cells[r][c] = value
			widths[c] = math.max(widths[c], Text.width(value))
		end
		if all_ws then
			widths[c] = 0
			for _, cell in ipairs(cells) do
				cell[c] = ""
			end
		end
		total = total + widths[c]
	end
	return cells, widths, total
end

function Table:layout(opts)
	local cells, widths = self:cells(opts)
	local free = opts.width
	for c, col in ipairs(self.cols) do
		if not col.width then
			free = free - widths[c]
		end
	end
	free = math.max(free, 0)
	for c, col in ipairs(self.cols) do
		if col.width then
			widths[c] = M.dim(widths[c], free, { max = col.width })
			free = free - widths[c]
		end
	end
	local ret = {}
	for _, row in ipairs(cells) do
		local line, remaining = {}, opts.width
		for c, col in ipairs(self.cols) do
			local width = math.min(widths[c], math.max(0, remaining))
			line[#line + 1] = { value = Text.fit(row[c], width, col.align, self.ellipsis), hl = col.hl }
			remaining = remaining - width
		end
		ret[#ret + 1] = line
	end
	return ret
end

M.new = Table.new
return M
