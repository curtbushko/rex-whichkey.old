-- Pure Lua 5.1 geometry shared by Rex's controller and the terminal renderer.
-- Overlay is the current Rex clipping workaround; native uses documented bounds.
local M = {}
local positions = { top = true, bottom = true, left = true, right = true, center = true }
-- Only position crosses the user-config boundary. Low-level geometry options
-- below are implementation details, including the eventual native-backend switch.
function M.options(window, viewport, position)
	window = window or {}
	assert(type(window) == "table", "window must be a table containing only position")
	for key in pairs(window) do
		assert(key == "position", "Unknown window option: " .. tostring(key) .. "; only position is configurable")
	end
	local selected = position or window.position or "bottom"
	assert(positions[selected], "Unknown rendering area: " .. tostring(selected))
	return { position = selected, cols = viewport.cols, rows = viewport.rows }
end
local function number(value, fallback, minimum)
	value = value == nil and fallback or value
	assert(
		type(value) == "number" and value == value and value < math.huge and value >= minimum,
		"Invalid area dimension"
	)
	return value
end
local function plan(position, opts, content_rows)
	opts = opts or {}
	local cols = math.max(1, math.floor(number(opts.cols, 80, 1)))
	local rows = math.max(1, math.floor(number(opts.rows, 24, 1)))
	local backend = opts.backend or "overlay"
	assert(backend == "overlay" or backend == "native", "Unknown area backend: " .. tostring(backend))
	local bar = position == "top" or position == "bottom"
	local gap = math.floor(number(opts.gap, 2, 0))
	local gx = bar and 0 or math.min(gap, math.floor((cols - 1) / 2))
	local gy = bar and 0 or math.min(gap, math.max(0, math.floor((rows - 8) / 2)))
	local width = number(opts.width, 0.45, 0.000001)
	if width <= 1 then
		width = math.floor(cols * width)
	end
	width = bar and cols or math.max(1, math.min(math.floor(width), cols - gx * 2))
	local fraction = number(opts.max_height, 0.5, 0.000001)
	assert(fraction <= 1, "max_height must be at most one")
	local available = rows - gy * 2
	local limit = math.min(available, math.max(math.min(8, available), math.floor(rows * fraction)))
	local height = content_rows and math.min(limit, number(content_rows, 1, 1) + 2) or limit
	height = math.max(1, math.floor(height))
	local x = position == "left" and gx + 1
		or position == "right" and cols - gx - width + 1
		or math.floor((cols - width) / 2) + 1
	local y = position == "top" and 1
		or position == "bottom" and rows - height + 1
		or math.floor((rows - height) / 2) + 1
	local border = not bar and width >= 4 and height >= 4
	local px, py = border and 1 or 0, height >= 3 and 1 or 0
	local bounds = { x = 0, y = 0, w = 1, h = 1 }
	if backend == "native" then
		bounds = { x = (x - 1) / cols, y = (y - 1) / rows, w = width / cols, h = height / rows }
	end
	return {
		position = position,
		backend = backend,
		bounds = bounds,
		full_width = bar,
		border = border,
		box = { x = x, y = y, cols = width, rows = height },
		content = { x = x + px, y = y + py, cols = math.max(1, width - px * 2), rows = math.max(1, height - py * 2) },
	}
end
function M.top(opts, content_rows)
	return plan("top", opts, content_rows)
end
function M.bottom(opts, content_rows)
	return plan("bottom", opts, content_rows)
end
function M.left(opts, content_rows)
	return plan("left", opts, content_rows)
end
function M.right(opts, content_rows)
	return plan("right", opts, content_rows)
end
function M.center(opts, content_rows)
	return plan("center", opts, content_rows)
end
function M.resolve(opts, content_rows)
	local position = opts.position or "bottom"
	assert(positions[position], "Unknown rendering area: " .. tostring(position))
	return M[position](opts, content_rows)
end
-- Measure with the maximum available height, then shrink to actual rendered rows.
function M.render(opts, render)
	local area = M.resolve(opts)
	local result = render({ cols = area.content.cols, rows = area.content.rows, full_width = area.full_width })
	area = M.resolve(opts, #result.lines)
	result = render({ cols = area.content.cols, rows = area.content.rows, full_width = area.full_width })
	result.area = area
	return result
end
local function clip(value, width)
	local Text = require("text") -- Only the terminal renderer needs the UTF-8 library.
	local ret, cells, i = {}, 0, 1
	while i <= #value do
		local escape = value:match("^\27%[[0-?]*[ -/]*[@-~]", i)
		if escape then
			ret[#ret + 1], i = escape, i + #escape
		else
			local char = value:match("^[%z\1-\127\194-\244][\128-\191]*", i) or value:sub(i, i)
			local size = Text.width(char)
			if cells + size > width then
				break
			end
			ret[#ret + 1], cells, i = char, cells + size, i + #char
		end
	end
	return table.concat(ret)
end
function M.draw(area, lines, styles)
	styles = styles or {}
	local b, c = area.box, area.content
	local dx, dy = 0, 0
	if area.backend == "native" then
		dx, dy = 1 - b.x, 1 - b.y
	end
	local out = { "\27[0m\27[3J\27[2J\27[?25l" }
	local bg, fg, border = styles.background or "", styles.text or "", styles.border or ""
	local function put(x, y, text)
		out[#out + 1] = string.format("\27[%d;%dH", y + dy, x + dx) .. bg .. text
	end
	local rounded = area.border and not styles.ascii
	for row = 0, b.rows - 1 do
		local inset = rounded and (row == 0 or row == b.rows - 1) and 1 or 0
		put(b.x + inset, b.y + row, string.rep(" ", b.cols - 2 * inset))
	end
	if area.border then
		local tl, tr, bl, br, horizontal, vertical = "╭", "╮", "╰", "╯", "─", "│"
		if styles.ascii then
			tl, tr, bl, br, horizontal, vertical = "+", "+", "+", "+", "-", "|"
		end
		if rounded then
			for _, edge in ipairs({ { b.y, tl, tr }, { b.y + b.rows - 1, bl, br } }) do
				put(b.x, edge[1], border .. edge[2])
				put(b.x + 1, edge[1], border .. string.rep(horizontal, b.cols - 2))
				put(b.x + b.cols - 1, edge[1], border .. edge[3])
			end
		else
			put(b.x, b.y, border .. tl .. string.rep(horizontal, b.cols - 2) .. tr)
			put(b.x, b.y + b.rows - 1, border .. bl .. string.rep(horizontal, b.cols - 2) .. br)
		end
		for row = 1, b.rows - 2 do
			put(b.x, b.y + row, border .. vertical)
			put(b.x + b.cols - 1, b.y + row, border .. vertical)
		end
	end
	for row = 1, math.min(#lines, c.rows) do
		put(c.x, c.y + row - 1, fg .. clip(lines[row], c.cols))
	end
	out[#out + 1] = "\27[0m"
	return table.concat(out)
end
return M
