-- Rex Lua 5.1 plugin entry point. Runtime paths are filled by the package.
local M = {}
local directory = "@REX_WHICHKEY_DIRECTORY@"
local command = "@REX_WHICHKEY_COMMAND@"
local cli = "@REX_CLI@"
local Mappings = dofile(directory .. "/mappings.lua")
local Areas = dofile(directory .. "/areas.lua")
local defaults = dofile(directory .. "/config.lua")
local function checked(result, err)
	if err then
		error(err, 0)
	end
	return result
end

function M.setup(opts)
	opts = opts or {}
	local allowed = { position = true, spec = true, title = true, icon = true, icons = true }
	for key in pairs(opts) do
		assert(allowed[key], "Unknown which-key option: " .. tostring(key))
	end
	local config = {
		window = { position = opts.position or defaults.window.position },
		spec = opts.spec or defaults.spec,
		title = opts.title or defaults.title,
		icon = opts.icon or defaults.icon,
		icons = opts.icons or defaults.icons,
	}
	Areas.options(config.window, { cols = 1, rows = 1 })
	assert(type(config.spec) == "table", "which-key spec must be a table")

	rex.action({
		name = "whichkey_snapshot",
		title = "Which-key Menu Data",
		run = function()
			return Mappings.new(config):snapshot(config.window.position)
		end,
	})
	rex.action({
		name = "whichkey",
		title = "Which-key Menu",
		args = { position = "string?" },
		run = function(ctx, args)
			assert(ctx.client_id and ctx.session_id and ctx.block_id, "Which-key needs a client, session and pane")
			local position = (args and args.position) or config.window.position
			Areas.options({ position = position }, { cols = 1, rows = 1 })
			local view = checked(rex.session.view({}))
			local window
			for _, candidate in ipairs(view.windows or {}) do
				for _, layer in ipairs(candidate.layers or {}) do
					for _, block in ipairs(layer.blocks or {}) do
						if block.block_id == ctx.block_id then
							window = candidate
						end
					end
				end
			end
			assert(window, "Originating pane is no longer in the session")
			-- Inherit the theme and bypass login initialization. Areas own geometry.
			return checked(rex.session.new_layer({
				window_id = window.window_id,
				bounds = { x = 0, y = 0, w = 1, h = 1 },
				focus = true,
				layout = rex.layout.block({
					label = "whichkey-popup",
					flavor = "com.superlogical.terminal.shell",
					options = {
						shell = "none",
						login = false,
						command = {
							command,
							cli,
							ctx.client_id,
							ctx.session_id,
							ctx.block_id,
							-- Internal fallbacks, used only when OSC queries fail.
							"#3d484d",
							"#d3c6aa",
							"#dbbc7f",
							"#859289",
							"#9da9a0",
							"#e67e80",
							"#7fbbb3",
							"1",
							"1",
							position,
						},
						exit = { on_completion = true, quick_exit_threshold_ms = 0 },
					},
				}),
			}))
		end,
	})
	rex.action({
		name = "whichkey_dispatch",
		title = "Run Which-key Choice",
		args = { lhs = "string", confirmed = "boolean?" },
		run = function(ctx, args)
			local mapping = assert(Mappings.new(config):get(args.lhs), "Unknown which-key mapping")
			assert(mapping.action and not mapping.is_group, "Which-key mapping is a submenu")
			assert(not mapping.confirm or args.confirmed == true, "Which-key mapping needs confirmation")
			assert(ctx.block_id, "Which-key needs the originating pane")
			checked(rex.session.focus_block({ block_id = ctx.block_id }))
			if type(mapping.action) == "function" then
				return mapping.action(ctx, mapping.args or {})
			end
			return rex.client.queue(mapping.action, mapping.args or {})
		end,
	})
end
return M
