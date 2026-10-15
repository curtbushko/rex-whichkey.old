package.path = "lua/whichkey/?.lua;" .. package.path
local Mappings = require("mappings")
local State = require("state")
local Renderer = require("renderer")
-- Default entries must declare their own icons, including scoped/generated items.
local defaults = require("config")
local default_tree = Mappings.new(defaults)
local function check_icons(spec)
	for _, entry in ipairs(spec) do
		if type(entry[1]) == "string" then
			assert(type(entry.icon) == "string" and entry.icon ~= "", "missing explicit icon: " .. entry[1])
			assert(default_tree:get(entry[1]).icon == entry.icon)
			local prefix, key = entry[1]:sub(1, -2), entry[1]:sub(-1)
			local normal = State.display(default_tree, { prefix = prefix }, false)
			local ascii = State.display(default_tree, { prefix = prefix }, true)
			local found = false
			for i, item in ipairs(normal) do
				if item[1] == key then
					assert(item[2]:find(entry.icon, 1, true), "display the explicit icon")
					assert(not ascii[i][2]:find(entry.icon, 1, true), "omit Nerd Font icons in ASCII mode")
					found = true
				end
			end
			assert(found, "default item is reachable: " .. entry[1])
		else
			check_icons(entry)
		end
	end
end
check_icons(defaults.spec)
local callback = function()
	return "callback"
end
local config = {
	title = "Test",
	icon = "",
	spec = {
		{ "g", group = "Tools", icon = "" },
		{ "gn", group = "Nested" },
		{ "gnr", "pane.split", desc = "Split right", args = { direction = "right" } },
		{ "gnm", group = "More" },
		{
			"gnmz",
			callback,
			desc = "Custom callback",
			icon = function()
				return "!"
			end,
		},
		{ "g<Space>", "client.palette.toggle", desc = "Palette" },
		{
			confirm = true,
			icon = "x",
			{ "gx", "pane.close", desc = "Close pane" },
			{ "gy", "pane.zoom", desc = "Zoom", confirm = false },
		},
		{ "h", "pane.zoom", desc = "Hidden", hidden = true },
		{ "d", "pane.zoom", desc = "Disabled", cond = false },
		{ "q", "pane.zoom", desc = "Q is customizable" },
	},
}
local tree = Mappings.new(config)
local snapshot = tree:snapshot("left")
local restored_config = Mappings.config_from_snapshot(snapshot)
local restored = Mappings.new(restored_config)
assert(restored_config.window.position == "left")
assert(restored:get("gnmz").action and restored:get("gnmz").icon == "!")
assert(restored:get("gx").confirm and not restored:get("d"))
assert(restored:get("h").hidden and restored:get("q"))
assert(tree:get("gnmz").action == callback, "callbacks stay in Rex, not the snapshot")
for _, entry in ipairs(snapshot.entries) do
	assert(entry.args == nil and type(entry.action) == "boolean")
end
assert(State.display(restored, { prefix = "gn" }, false).title == State.display(tree, { prefix = "gn" }, false).title)
assert(not pcall(Mappings.config_from_snapshot, { version = 999 }))
assert(tree:get("gnr").action == "pane.split" and tree:get("gnr").args.direction == "right")
assert(tree:get("gx").confirm and not tree:get("gy").confirm)
assert(tree:get("gx").icon == "x" and tree:get("gnmz").icon == "!")
assert(tree:get("gnmz").action == callback)
assert(not tree:get("d") and tree:get("h").hidden)
local display = State.display(tree, { prefix = "g", page = 0 }, false)
assert(display.title:find("Test » Tools", 1, true))
assert(display[1][1] == "n" and display[1].group)
assert(display[2][1] == "Space")
assert(State.display(tree, { prefix = "" }, true).title == "Test > Which-key")
local root_display = State.display(tree, { prefix = "" }, false)
for _, item in ipairs(root_display) do
	assert(item[1] ~= "h" and item[1] ~= "d")
end
local function step(state, key, pages)
	return State.step(tree, state or { prefix = "", page = 0, confirmation = "" }, key, pages or 1)
end
local event = step(nil, "g")
assert(event.kind == "render" and event.prefix == "g")
event = step(event, "n")
assert(event.prefix == "gn")
event = step(event, "m")
assert(event.prefix == "gnm")
local back = step(event, "\27")
assert(back.prefix == "gn", "Escape goes back exactly one level")
back = step(back, "\127")
assert(back.prefix == "g")
local selected = step(event, "z")
assert(selected.kind == "dispatch" and selected.lhs == "gnmz" and not selected.confirmed)
selected = step({ prefix = "g" }, " ")
assert(selected.lhs == "g<Space>")
local confirm = step({ prefix = "g" }, "x")
assert(confirm.kind == "render" and confirm.confirmation == "gx")
assert(State.display(tree, confirm, true).title:find("Close pane", 1, true))
selected = step(confirm, "y")
assert(selected.kind == "dispatch" and selected.lhs == "gx" and selected.confirmed)
local cancel = step(confirm, "\27")
assert(cancel.prefix == "g" and cancel.confirmation == "")
assert(step(cancel, "q").kind == "quit")
assert(step(nil, "q").lhs == "q", "configured q overrides the close shortcut")
assert(step(nil, "\27").kind == "quit")
assert(step(nil, "?").kind == "render")
assert(step({ prefix = "g", page = 0 }, "\t", 3).page == 1)
-- One config drives deep navigation, icons, renderer output, and action identity.
local data = State.display(tree, { prefix = "gnm" }, false)
local rendered = Renderer.render({ prefix = "gnm", cols = 100, rows = 20, full_width = true, menu = data })
assert(table.concat(rendered.lines):find("Custom callback", 1, true))
assert(table.concat(rendered.lines):find("!", 1, true))
local ascii = State.display(tree, { prefix = "g" }, true)
assert(not table.concat({ ascii[1][2], ascii[2][2] }):find("", 1, true))
local out_of_order = Mappings.new({
	spec = {
		{ "abc", "pane.zoom", desc = "Zoom" },
		{ "ab", group = "Inner" },
		{ "a", group = "Outer" },
		{ "empty", group = "Empty" },
		{
			cond = function()
				return nil
			end,
			{ "disabled", "pane.zoom", desc = "Disabled scope" },
		},
	},
})
assert(out_of_order:get("ab").group == "Inner" and out_of_order:get("abc").action == "pane.zoom")
assert(not out_of_order:get("disabled"))
local empty = State.display(out_of_order, { prefix = "empty" }, true)
assert(#empty == 0)
local empty_rendered = Renderer.render({ prefix = "empty", cols = 80, rows = 20, menu = empty })
assert(table.concat(empty_rendered.lines):find("No entries", 1, true))
local q_rendered = Renderer.render({ prefix = "", cols = 100, rows = 20, menu = root_display })
assert(not q_rendered.lines[#q_rendered.lines]:find("q close", 1, true))
-- Invalid or ambiguous specs fail with errors rather than silently dropping keys.
for _, spec in ipairs({
	{ { "a", "pane.zoom" } },
	{ { "a", "pane.zoom", desc = "One" }, { "a", "pane.close", desc = "Two" } },
	{ { "a", "pane.zoom", desc = "Leaf" }, { "ab", "pane.close", desc = "Child" } },
	{ { "a", group = "Group", mode = "n" } },
	{ { "a", "pane.zoom", desc = "Bad args", args = "wrong" } },
	{ { "<C-x>", "pane.zoom", desc = "Unsupported key" } },
}) do
	assert(not pcall(Mappings.new, { spec = spec }))
end
print("Rex which-key shared spec, inherited settings, arbitrary nesting, icons and input: passed")
