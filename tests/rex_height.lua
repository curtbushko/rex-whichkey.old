-- Rex controller contract: measure the source window and isolate backend changes.
local directory = os.getenv("REX_WHICHKEY_LUA_DIR") or "lua/whichkey"
local real_dofile = dofile
local view, size, calls, resize_error, size_error, settings, backend
rex = {
	block_id = "origin",
	args = { rows = 6, directory = directory },
	block = {
		call = function(creator, method, args)
			assert(creator == "com.superlogical.terminal" and method == "size" and args.block_id == "origin")
			return size, size_error
		end,
	},
	session = {
		view = function()
			return view
		end,
		resize_layer = function(args)
			calls[#calls + 1] = args
			if resize_error then
				return nil, resize_error
			end
			return {}
		end,
	},
}
dofile = function(path)
	if path == directory .. "/config.lua" then
		return { window = settings }
	end
	if path == directory .. "/areas.lua" then
		local areas = real_dofile(path)
		local resolve = areas.resolve
		areas.resolve = function(opts, rows)
			opts.backend = backend -- Exercise internal backends, not user configuration.
			return resolve(opts, rows)
		end
		return areas
	end
	return real_dofile(path)
end
local function reset()
	settings, backend = { position = "bottom" }, "overlay"
	size, calls, resize_error, size_error = { rows = 60, columns = 200 }, {}, nil, nil
	rex.args.rows, rex.args.position = 6, nil
	view = {
		windows = {
			{
				window_id = "window",
				layers = {
					{
						kind = "tiled",
						layout = { block_id = "origin", rect = { 0, 0, 1, 1 } },
						blocks = { { block_id = "origin" } },
					},
					{
						kind = "floating",
						layer_id = "menu",
						bounds = { 0, 0, 1, 1 },
						blocks = { { label = "whichkey-popup" } },
					},
				},
			},
		},
	}
end
local function run()
	return real_dofile(directory .. "/resize.lua")
end
reset()
local dimensions = run()
assert(dimensions[1] == 200 and dimensions[2] == 60 and #calls == 0)
-- Production preserves the full-window layer; native resizing remains opt-in internally.
reset()
backend = nil
run()
assert(#calls == 0, "the default backend must not resize the popup layer")
reset()
-- Overlay content grows without changing its layer bounds.
rex.args.rows = 1000
run()
assert(#calls == 0)
-- Native rectangles use width/height semantics and only resize when changed.
reset()
backend = "native"
run()
assert(#calls == 1 and calls[1].layer_id == "menu")
local b = calls[1].bounds
assert(b.x == 0 and b.w == 1 and math.abs(b.h - 8 / 60) < 1e-9)
assert(math.abs(b.y + b.h - 1) < 1e-9)
view.windows[1].layers[2].bounds = { b.x, b.y, b.w, b.h }
calls = {}
run()
assert(#calls == 0)
rex.args.rows = 5
run()
assert(math.abs(calls[1].bounds.h - 7 / 60) < 1e-9)
-- Measurement pass never changes layout, and split-pane dimensions infer the whole window.
reset()
backend = "native"
rex.args.rows = 0
size = { rows = 30, columns = 100 }
view.windows[1].layers[1].layout = {
	rect = { 0, 0, 1, 1 },
	split = {
		before = { block_id = "other", rect = { 0, 0, 0.5, 1 } },
		after = {
			rect = { 0.5, 0, 0.5, 1 },
			split = {
				before = { block_id = "above", rect = { 0.5, 0, 0.5, 0.5 } },
				after = { block_id = "origin", rect = { 0.5, 0.5, 0.5, 0.5 } },
			},
		},
	},
}
dimensions = run()
assert(dimensions[1] == 200 and dimensions[2] == 60 and #calls == 0)
-- Position overrides and all five geometries share the same controller.
for _, position in ipairs({ "top", "bottom", "left", "right", "center" }) do
	reset()
	backend = "native"
	rex.args.position = position
	run()
	b = calls[1].bounds
	assert(b.x >= 0 and b.y >= 0 and b.x + b.w <= 1 + 1e-9 and b.y + b.h <= 1 + 1e-9)
end
reset()
backend, resize_error = "native", "resize failed"
assert(not pcall(run))
reset()
view.windows[1].layers[2].blocks[1].label = "unrelated"
assert(not pcall(run) and #calls == 0)
reset()
size_error, size = "unavailable", nil
assert(not pcall(run) and #calls == 0)
reset()
view.windows[1].layers[1].layout = { block_id = "other", rect = { 0, 0, 1, 1 } }
assert(not pcall(run) and #calls == 0, "missing origin geometry must not resize the popup")
reset()
size.rows = 0
assert(not pcall(run) and #calls == 0)
reset()
rex.args.rows = -1
assert(not pcall(run))
reset()
settings.backend = "native"
assert(not pcall(run) and #calls == 0, "user configuration cannot choose an internal backend")
dofile = real_dofile
print("Rex placement controller, backend geometry, measurement and errors: passed")
