-- Rex Lua 5.1 controller. Rendering areas own all placement/backend policy.
local directory = assert(rex.args.directory, "Missing menu resource directory")
local Areas = dofile(directory .. "/areas.lua")
local Config = dofile(directory .. "/config.lua")
local function checked(result, err)
	assert(result, err)
	return result
end
local requested = tonumber(rex.args.rows) or 0
assert(requested >= 0 and requested < math.huge and requested == math.floor(requested), "Invalid requested menu height")
local view = checked(rex.session.view({}))
local window, origin
for _, candidate in ipairs(view.windows or {}) do
	for _, layer in ipairs(candidate.layers or {}) do
		for _, block in ipairs(layer.blocks or {}) do
			if block.block_id == rex.block_id then
				window, origin = candidate, block
			end
		end
	end
end
assert(window and origin, "Originating pane is no longer in the session")
local popup
for i = #window.layers, 1, -1 do
	local layer = window.layers[i]
	if layer.kind == "floating" then
		for _, block in ipairs(layer.blocks or {}) do
			if block.label == "whichkey-popup" then
				popup = layer
				break
			end
		end
	end
	if popup then
		break
	end
end
assert(popup, "No which-key layer in the originating window")
local size = checked(rex.block.call("com.superlogical.terminal", "size", { block_id = rex.block_id }))
assert(
	size.rows
		and size.rows > 0
		and size.columns
		and size.columns > 0
		and origin.rect
		and origin.rect.h > 0
		and origin.rect.w > 0,
	"Originating pane has no usable terminal dimensions"
)
local opts = Areas.options(Config.window, {
	cols = math.max(1, math.floor(size.columns / origin.rect.w + 0.5)),
	rows = math.max(1, math.floor(size.rows / origin.rect.h + 0.5)),
}, rex.args.position)
local area = Areas.resolve(opts, requested > 0 and requested or nil)
if requested > 0 then
	local b, previous = area.bounds, popup.bounds
	if
		not previous
		or math.abs(previous.x - b.x) > 1e-6
		or math.abs(previous.y - b.y) > 1e-6
		or math.abs(previous.w - b.w) > 1e-6
		or math.abs(previous.h - b.h) > 1e-6
	then
		checked(rex.session.resize_layer({ layer_id = popup.layer_id, bounds = b }))
	end
end
-- Fixed numeric array; the Bash transport validates it, never evaluates code.
return { opts.cols, opts.rows }
