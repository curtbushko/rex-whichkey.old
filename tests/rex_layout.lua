-- Run with the Lua/luautf8 environment used by rex-whichkey.nix.
package.path = "lua/whichkey/?.lua;" .. package.path
local Layout = require("layout")
local Text = require("text")
local Renderer = require("renderer")

assert(Layout.dim(0.5, 80) == 40)
assert(Layout.dim(-4, 80) == 76)
assert(Layout.dim(12, 80, { min = 20, max = 60 }) == 20)
assert(Layout.dim(100, 80, { max = 60 }) == 60)
assert(Text.width("你好") == 4 and Text.width("é") == 1)
assert(Text.width("󰙅") == 1 and Text.width("") == 1)
assert(Text.clip("你好world", 3) == "你")
assert(Text.width(Text.fit("你好world", 5)) == 5)
assert(Text.fit("x", 4, "right") == "   x")
assert(Text.fit("x", 4, "center") == " x  ")
assert(Text.fit("hello", 0) == "")

local t = Layout.new({
	cols = { { key = "key", align = "right" }, { key = "desc", width = math.huge } },
	rows = { { key = "w", desc = "你好world" }, { key = "1-9", desc = "Tabs" } },
})
local _, widths, total = t:cells()
assert(widths[1] == 4 and total == 13)
local laid = t:layout({ width = 10 })
assert(laid[1][1].value == "  w ")
for _, row in ipairs(laid) do
	local line = ""
	for _, cell in ipairs(row) do
		line = line .. cell.value
	end
	assert(Text.width(line) <= 10, "Unicode truncation must fit the available cells")
end

local function render(extra)
	local opts = { prefix = "", cols = 100, rows = 30, ascii = true }
	for k, v in pairs(extra or {}) do
		opts[k] = v
	end
	return Renderer.render(opts)
end
local wide = render({ full_width = true, cols = 200, rows = 12 })
assert(wide.width == 200 and wide.margin == 0, "classic layout must use the full viewport")
assert(wide.columns > 2 and #wide.lines <= 7, "wide menus should gain columns instead of height")
assert(table.concat(wide.lines):find("Command palette", 1, true))
for _, line in ipairs(wide.lines) do
	assert(Text.width(line) == 200)
end
local many = { title = "Many items" }
for i = 1, 100 do
	many[#many + 1] = { tostring(i), "Item " .. i }
end
local growing = render({ full_width = true, cols = 100, rows = 6, menu = many })
assert(growing.desired_rows > growing.rows, "measure natural content height before clipping/paging")
assert(growing.pages > 1)
local expanded = render({ full_width = true, cols = 100, rows = growing.desired_rows, menu = many })
assert(expanded.pages == 1 and #expanded.lines == expanded.desired_rows, "the requested height must fit the whole menu")
assert(wide.desired_rows < growing.desired_rows, "small menus must shrink again")
local r = render()
assert(r.columns == 2 and r.pages == 1)
assert(r.margin == math.floor((r.cols - r.width) / 2), "center measured content, not a guessed width")
local all = table.concat(r.lines, "\n")
assert(all:find("Command palette", 1, true) and all:find("q close", 1, true))
assert(r.lines[#r.lines]:find("Esc/q close", 1, true), "root has one contextual footer")
assert(not all:find("Select a highlighted key", 1, true), "do not repeat instructions on a second footer row")
-- Which-key's view lays out column-major rather than alternating across columns.
assert(r.lines[3]:find("[w]", 1, true) and r.lines[3]:find("[z]", 1, true))
for _, dimensions in ipairs({ { 121, 42 }, { 80, 24 }, { 65, 18 }, { 32, 10 }, { 18, 8 }, { 8, 3 }, { 1, 1 } }) do
	r = render({ cols = dimensions[1], rows = dimensions[2] })
	assert(#r.lines <= dimensions[2])
	for _, line in ipairs(r.lines) do
		assert(Text.width(line) <= dimensions[1], "renderer must not overflow small viewports")
	end
	r = render({ cols = dimensions[1], rows = dimensions[2], full_width = true })
	assert(#r.lines <= dimensions[2])
	for _, line in ipairs(r.lines) do
		assert(Text.width(line) == dimensions[1], "full-width layout must fit narrow viewports too")
	end
end
r = render({ cols = 32, rows = 10, page = 1 })
assert(r.page == 1 and r.pages == 2)
assert(table.concat(r.lines, "\n"):find("page 2/2", 1, true))
r = render({ cols = 140, rows = 40, width_fraction = 4 / 7, height_fraction = 6 / 13 })
assert(r.cols == 80 and r.rows == 18)
assert(r.margin == math.floor((80 - r.width) / 2))
for _, prefix in ipairs({ "", "w", "t", "f" }) do
	r = render({ prefix = prefix, ascii = false })
	assert(#r.lines > 0)
	local instructions = 0
	for _, line in ipairs(r.lines) do
		if line:find("Esc", 1, true) then
			instructions = instructions + 1
		end
	end
	assert(instructions == 1, "render Escape instructions only once")
	for _, line in ipairs(r.lines) do
		assert(Text.width(line) <= r.cols)
	end
end
local plain = render()
r = render({ styles = { text = "\27[39m", key = "\27[1;33m", title = "\27[1;36m", normal = "\27[22m" } })
for i, line in ipairs(r.lines) do
	assert(line:gsub("\27%[[0-9;]*m", "") == plain.lines[i], "ANSI styling must not affect measurement")
end
r = render({ page = 100 })
assert(r.page == 0, "resize must clamp stale page indices")
r = render({ confirmation = "x" })
assert(table.concat(r.lines, "\n"):find("Confirm: Close pane", 1, true))
r = render({ notice = "\27[2Jbad\r\ncontrol" })
assert(not table.concat(r.lines):find("\27", 1, true), "untrusted notices cannot inject terminal escapes")
assert(table.concat(r.lines):find("Action failed", 1, true))
print("Rex which-key Lua dimensions, Unicode layout, centering, paging and bounds: passed")
