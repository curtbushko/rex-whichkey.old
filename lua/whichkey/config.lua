-- which-key-style spec: full key sequences, group/desc/icon metadata, and
-- nested attribute scopes. Rex extensions: args and confirm. See README.md.
local spec = {
	{ "w", group = "Sessions", icon = "󰙅" },
	{ "wn", "session.new", desc = "New session", icon = "" },
	{ "ws", "session.switch", desc = "Switch session", icon = "󰒺" },
	{ "wh", "session.previous", desc = "Previous", icon = "" },
	{ "wl", "session.next", desc = "Next", icon = "" },
	{ "wr", "session.rename", desc = "Rename", icon = "󰏫" },
	{ "t", group = "Tabs", icon = "" },
	{ "tn", "client.tab.new", desc = "New tab", icon = "" },
	{ "th", "client.tab.previous", desc = "Previous", icon = "" },
	{ "tl", "client.tab.next", desc = "Next", icon = "" },
	{ "tr", "client.tab.rename", desc = "Rename", icon = "󰏫" },
	{ "v", "pane.split", desc = "Split right", icon = "", args = { direction = "right" } },
	{ "s", "pane.split", desc = "Split down", icon = "", args = { direction = "down" } },
	{ "f", group = "Focus", icon = "󱡁" },
	{ "fh", "pane.focus", desc = "Left", icon = "", args = { direction = "left" } },
	{ "fj", "pane.focus", desc = "Down", icon = "", args = { direction = "down" } },
	{ "fk", "pane.focus", desc = "Up", icon = "", args = { direction = "up" } },
	{ "fl", "pane.focus", desc = "Right", icon = "", args = { direction = "right" } },
	{ "z", "pane.zoom", desc = "Zoom pane", icon = "󰊓" },
	{ "e", "client.sidebar.toggle", desc = "Sidebar", icon = "󰙀" },
	{ "c", "client.palette.toggle", desc = "Command palette", icon = "" },
	{
		confirm = true,
		{ "x", "pane.close", desc = "Close pane", icon = "󰅖" },
		{ "tx", "client.tab.close", desc = "Close tab", icon = "󰅖" },
		{ "wx", "session.close", desc = "Close session", icon = "󰅖" },
	},
}
for i = 1, 9 do
	spec[#spec + 1] = { "t" .. i, "client.tab.goto", desc = "Go to tab " .. i, icon = "", args = { index = i } }
end

return {
	window = { position = "center" }, -- top | bottom | left | right | center
	title = "Rex",
	icon = "",
	icons = { breadcrumb = "»", group = "+" },
	spec = spec,
}
