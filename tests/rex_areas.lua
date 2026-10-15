package.path = (os.getenv("REX_WHICHKEY_LUA_DIR") or "lua/whichkey") .. "/?.lua;" .. package.path
local Areas = require("areas")
local Renderer = require("renderer")
local Config = require("config")
for key in pairs(Config.window) do
	assert(key == "position", "only position belongs in user config")
end
local public = Areas.options({ position = "left" }, { cols = 100, rows = 40 })
assert(public.position == "left" and public.cols == 100 and public.rows == 40)
assert(
	Areas.resolve(public).backend == "overlay",
	"keep the overlay workaround until native layers are verified in Rex"
)
assert(Areas.options(nil, { cols = 100, rows = 40 }, "top").position == "top")
for _, key in ipairs({ "backend", "width", "max_height", "gap", "cols", "rows" }) do
	assert(not pcall(Areas.options, { [key] = 1 }, { cols = 100, rows = 40 }), "reject private user settings: " .. key)
end
local menu = { title = "Placement test", { "a", "Alpha" }, { "b", "Beta" } }
local function render(position, extra)
	local opts =
		{ position = position, backend = "overlay", cols = 100, rows = 40, width = 40, gap = 2, max_height = 0.5 }
	for k, v in pairs(extra or {}) do
		opts[k] = v
	end
	return Areas.render(opts, function(viewport)
		return Renderer.render({
			cols = viewport.cols,
			rows = viewport.rows,
			full_width = viewport.full_width,
			menu = menu,
			ascii = true,
		})
	end)
end
for _, name in ipairs({ "top", "bottom", "left", "right", "center" }) do
	assert(type(Areas[name]) == "function", "consistent named placement functions")
	local r = render(name)
	local b = r.area.box
	assert(b.x >= 1 and b.y >= 1 and b.x + b.cols - 1 <= 100 and b.y + b.rows - 1 <= 40)
	assert(r.area.bounds.x == 0 and r.area.bounds.y == 0 and r.area.bounds.w == 1 and r.area.bounds.h == 1)
	assert(r.area.content.cols >= 1 and r.area.content.rows >= 1)
	if name == "top" or name == "bottom" then
		assert(b.cols == 100 and b.x == 1 and r.area.full_width)
		assert(not r.area.border, "bars are full width without a box frame")
	else
		assert(b.cols == 40 and r.area.border and not r.area.full_width)
	end
	local frame = Areas.draw(r.area, r.lines, { ascii = true, background = "BG", text = "FG", border = "BD" })
	assert(frame:sub(1, 4) == "\27[0m", "reset background before clearing so unused cells stay unpainted")
	assert(frame:find("\27[2J", 1, true) and frame:find("Placement test", 1, true))
	if r.area.border then
		assert(frame:find("+", 1, true))
		local rounded = Areas.draw(r.area, r.lines, { background = "BG", border = "BD" })
		for _, corner in ipairs({
			{ b.x, b.y, "╭" },
			{ b.x + b.cols - 1, b.y, "╮" },
			{ b.x, b.y + b.rows - 1, "╰" },
			{ b.x + b.cols - 1, b.y + b.rows - 1, "╯" },
		}) do
			assert(
				rounded:find(string.format("\27[%d;%dHBGBD%s", corner[2], corner[1], corner[3]), 1, true),
				"rounded corner cells must retain the popup background"
			)
		end
	end
end
local top, bottom, left, right, center =
	render("top"), render("bottom"), render("left"), render("right"), render("center")
assert(top.area.box.y == 1)
assert(bottom.area.box.y + bottom.area.box.rows - 1 == 40)
assert(left.area.box.x == 3 and right.area.box.x + right.area.box.cols - 1 == 98)
assert(center.area.box.x == 31)
assert(math.abs((center.area.box.y - 1) * 2 + center.area.box.rows - 40) <= 1)
-- Native backend uses the identical logical layout, changing only layer geometry and local cursor coordinates.
for _, name in ipairs({ "top", "bottom", "left", "right", "center" }) do
	local overlay, native = render(name), render(name, { backend = "native" })
	local b, n = native.area.box, native.area.bounds
	assert(n.x == (b.x - 1) / 100 and n.y == (b.y - 1) / 40)
	assert(n.w == b.cols / 100 and n.h == b.rows / 40)
	assert(n.x + n.w <= 1 + 1e-9 and n.y + n.h <= 1 + 1e-9)
	assert(table.concat(overlay.lines, "\n") == table.concat(native.lines, "\n"))
	local frame = Areas.draw(native.area, native.lines, { ascii = true })
	assert(frame:find("\27[1;1H", 1, true), "native painting is local to the small layer")
end
-- Content-driven height, paging and tiny windows stay inside bounds.
local old = #menu
for i = 1, 80 do
	menu[#menu + 1] = { tostring(i), "A longer entry " .. i }
end
local large = render("bottom")
assert(large.area.box.rows <= 20 and large.pages > 1)
for i = #menu, old + 1, -1 do
	menu[i] = nil
end
assert(render("bottom").area.box.rows < large.area.box.rows)
for _, dimensions in ipairs({ { 1, 1 }, { 3, 2 }, { 12, 6 }, { 32, 10 } }) do
	for _, name in ipairs({ "top", "bottom", "left", "right", "center" }) do
		local r = render(name, { cols = dimensions[1], rows = dimensions[2] })
		local b = r.area.box
		assert(b.x >= 1 and b.y >= 1 and b.x + b.cols - 1 <= dimensions[1] and b.y + b.rows - 1 <= dimensions[2])
		assert(#r.lines <= r.area.content.rows)
		if dimensions[2] >= 10 then
			assert(table.concat(r.lines):find("Esc", 1, true), "reduce popup margins before dropping navigation help")
		end
		Areas.draw(r.area, r.lines, { ascii = true })
	end
end
assert(not pcall(render, "somewhere"))
assert(not pcall(render, "bottom", { backend = "guess" }))
assert(not pcall(render, "center", { width = 0 }))
-- Exercise the actual CLI protocol, including area overrides and ASCII frames.
local original_arg, original_write = arg, io.write
for _, position in ipairs({ "top", "bottom", "left", "right", "center" }) do
	local chunks = {}
	arg = { [0] = (os.getenv("REX_WHICHKEY_LUA_DIR") or "lua/whichkey") .. "/main.lua" }
	local values =
		{ "render", "", "0", "", "", "40", "100", "1", "1", "1", "", "", "", "", "", "", "", "", "", "ansi", position }
	for i, value in ipairs(values) do
		arg[i] = value
	end
	io.write = function(...)
		for i = 1, select("#", ...) do
			chunks[#chunks + 1] = tostring(select(i, ...))
		end
	end
	dofile(arg[0])
	io.write = original_write
	local output = table.concat(chunks)
	assert(output:match("^%d+ %d+ %d+\n\27%[0m"), "numeric metadata followed by a reset-first frame")
	assert(output:find("[w]", 1, true), "the actual menu is rendered")
	if position == "center" then
		assert(not output:find("\27[1;1H", 1, true), "centered overlay painting must keep window-relative coordinates")
	end
	if position ~= "top" and position ~= "bottom" then
		assert(output:find("+", 1, true))
	end
end
arg, io.write = original_arg, original_write
print("Rex five placement areas, backends, frames, sizing and tiny windows: passed")
