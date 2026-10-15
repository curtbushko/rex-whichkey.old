-- Formatting belongs to StyLua; Luacheck checks code and API usage.
std = "lua54"
max_line_length = false

for _, name in ipairs({ "areas", "config", "mappings", "plugin", "resize" }) do
	files["lua/whichkey/" .. name .. ".lua"] = { std = "lua51" }
end
files["lua/whichkey/plugin.lua"] = { std = "lua51", read_globals = { "rex" } }
files["lua/whichkey/resize.lua"] = { std = "lua51", read_globals = { "rex" } }
files["examples/*.lua"] = { std = "lua51", read_globals = { "rex" } }

-- Only these harnesses replace host globals/builtins. Production files do not.
files["tests/rex_height.lua"] = { globals = { "rex", "dofile" } }
files["tests/rex_plugin.lua"] = { globals = { "rex", "dofile" } }
stds.mock_io = {
	globals = {
		io = { read_only = true, fields = { write = { read_only = false } } },
	},
}
files["tests/rex_areas.lua"] = { std = "lua54+mock_io", globals = { "arg" } }
