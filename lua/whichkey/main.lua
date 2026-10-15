-- A line-based protocol between the Bash input loop and pure Lua menu logic.
-- Output is data only: numeric render metadata or a fixed six-line key event.
local directory = assert(arg[0]:match("^(.*[/])"), "Menu helper needs a path")
package.path = directory .. "?.lua;" .. package.path
local Mappings = require("mappings")
local State = require("state")
local Config = require("config")
local snapshot = os.getenv("REX_WHICHKEY_SNAPSHOT")
if snapshot and snapshot ~= "" then
	local value, _, err = require("dkjson").decode(snapshot)
	assert(value, err or "Invalid menu JSON")
	Config = Mappings.config_from_snapshot(value)
end
local Areas = require("areas")
local tree = Mappings.new(Config)
local mode = table.remove(arg, 1)
if mode == "key" then
	local event =
		State.step(tree, { prefix = arg[1], page = tonumber(arg[2]), confirmation = arg[3] }, arg[4], tonumber(arg[5]))
	io.write(
		table.concat(
			{ event.kind, event.prefix, tostring(event.page), event.confirmation, event.lhs, tostring(event.confirmed) },
			"\n"
		)
	)
	return
end
assert(mode == "render", "Expected render or key mode")
local Renderer = require("renderer")
local state = { prefix = arg[1], page = tonumber(arg[2]), confirmation = arg[3], notice = arg[4] }
local options = {
	prefix = state.prefix,
	page = state.page,
	confirmation = state.confirmation,
	notice = state.notice,
	menu = State.display(tree, state, arg[9] == "1"),
	rows = tonumber(arg[5]),
	cols = tonumber(arg[6]),
	width_fraction = tonumber(arg[7]),
	height_fraction = tonumber(arg[8]),
	ascii = arg[9] == "1",
	full_width = true,
	styles = {
		text = arg[10],
		key = arg[11] .. arg[16],
		border = arg[12],
		muted = arg[13],
		critical = arg[14],
		group = arg[15],
		title = arg[15] .. arg[16],
		normal = arg[17],
	},
}
local result
if arg[19] == "ansi" then
	local window = Areas.options(Config.window, { cols = options.cols, rows = options.rows }, arg[20])
	result = Areas.render(window, function(viewport)
		options.cols, options.rows = viewport.cols, viewport.rows
		options.full_width = viewport.full_width
		options.width_fraction, options.height_fraction = 1, 1
		return Renderer.render(options)
	end)
	io.write(
		result.page,
		" ",
		result.pages,
		" ",
		#result.lines,
		"\n",
		Areas.draw(result.area, result.lines, {
			background = arg[18],
			text = options.styles.text,
			border = options.styles.border,
			ascii = options.ascii,
		})
	)
else
	-- Plain output remains useful for pipes and input/dispatch integration tests.
	result = Renderer.render(options)
	io.write(result.page, " ", result.pages, " ", result.desired_rows, "\n", table.concat(result.lines, "\n"))
end
