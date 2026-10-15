local directory = os.getenv("REX_WHICHKEY_LUA_DIR") or "lua/whichkey"
local real_dofile = dofile
local actions, calls = {}, {}
local popup_error
local view = {
	windows = {
		{ window_id = "other", layers = {} },
		{ window_id = "origin-window", layers = { { blocks = { { block_id = "origin" } } } } },
	},
}
rex = {
	action = function(action)
		assert(not actions[action.name])
		actions[action.name] = action
	end,
	client = {
		queue = function(action, args)
			calls[#calls + 1] = { action = action, args = args }
		end,
	},
	layout = {
		block = function(options)
			return { block = options }
		end,
	},
	session = {
		view = function()
			return view
		end,
		new_layer = function(options)
			calls[#calls + 1] = options
			return { layer_id = "popup", block_ids = { "popup-block" } }, popup_error
		end,
		focus_block = function(args)
			calls[#calls + 1] = args
			return {}
		end,
	},
}
dofile = function(path)
	return real_dofile((path:gsub("@REX_WHICHKEY_DIRECTORY@", directory)))
end
local Plugin = real_dofile(directory .. "/plugin.lua")
for _, options in ipairs({ { backend = "native" }, { width = 60 }, { position = "invalid" } }) do
	assert(not pcall(Plugin.setup, options))
end
assert(next(actions) == nil, "invalid setup must not register partial actions")
local callback_args
Plugin.setup({
	position = "right",
	title = "Custom",
	icon = "!",
	spec = {
		{ "g", group = "Tools", icon = "+" },
		{ "gn", group = "Nested" },
		{
			"gnr",
			"pane.split",
			desc = function()
				return "Split right"
			end,
			args = { direction = "right" },
		},
		{
			"gx",
			function(ctx, args)
				callback_args = { ctx.block_id, args.value }
			end,
			desc = "Callback",
			confirm = true,
			args = { value = 42 },
		},
		{ "d", "pane.zoom", desc = "Disabled", cond = false },
	},
})
local snapshot = actions.whichkey_snapshot.run()
assert(snapshot.title == "Custom" and snapshot.position == "right")
local Mappings = real_dofile(directory .. "/mappings.lua")
local front = Mappings.new(Mappings.config_from_snapshot(snapshot))
assert(front:get("gnr").desc == "Split right" and front:get("gx").confirm and not front:get("d"))
-- Popup lifecycle remains host-independent: origin window, direct execution,
-- no login banner, and immediate cleanup even for quick exits.
local ctx = { client_id = "client", session_id = "session", block_id = "origin" }
actions.whichkey.run(ctx, {})
local layer = calls[1]
assert(#calls == 1 and layer.window_id == "origin-window" and layer.focus)
assert(layer.bounds.x == 0 and layer.bounds.y == 0 and layer.bounds.w == 1 and layer.bounds.h == 1)
local options = layer.layout.block.options
assert(options.shell == "none" and options.login == false)
assert(options.exit.on_completion and options.exit.quick_exit_threshold_ms == 0)
assert(options.command[3] == "client" and options.command[5] == "origin" and options.command[15] == "right")
calls = {}
actions.whichkey.run(ctx, { position = "left" })
assert(calls[1].layout.block.options.command[15] == "left")
calls = {}
assert(not pcall(actions.whichkey.run, ctx, { position = "invalid" }) and #calls == 0)
assert(not pcall(actions.whichkey.run, {}, {}) and #calls == 0)
assert(not pcall(actions.whichkey.run, { client_id = "client", session_id = "session", block_id = "gone" }, {}))
assert(#calls == 0)
popup_error = "creation failed"
assert(not pcall(actions.whichkey.run, ctx, {}))
popup_error, calls = nil, {}
assert(not pcall(actions.whichkey_dispatch.run, { block_id = "origin" }, { lhs = "gx" }))
assert(#calls == 0 and callback_args == nil)
actions.whichkey_dispatch.run({ block_id = "origin" }, { lhs = "gx", confirmed = true })
assert(callback_args[1] == "origin" and callback_args[2] == 42)
calls = {}
actions.whichkey_dispatch.run({ block_id = "origin" }, { lhs = "gnr" })
assert(#calls == 2 and calls[1].block_id == "origin" and calls[2].args.direction == "right")
dofile = real_dofile
print("Rex plugin setup, inline nested menus, snapshots, callbacks and confirmation: passed")
