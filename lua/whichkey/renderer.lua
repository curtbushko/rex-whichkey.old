-- Terminal backend for the column layout in folke/which-key.nvim's view.lua.
-- Apache-2.0; upstream revision 3aab2147e74890957785941f0c1ad87d0a44c15a.
-- Changes: explicit viewport dimensions, ANSI styles, paging, and Rex menu data;
-- no Neovim buffers, floating windows, keymap discovery, or event-loop dependency.
local Layout = require("layout")
local Text = require("text")
local M = {}

local Mappings = require("mappings")
local State = require("state")
local Config = require("config")

local function menu(opts)
	return State.display(Mappings.new(Config), opts, opts.ascii)
end

function M.render(opts)
	local cols = math.max(1, math.floor((tonumber(opts.cols) or 72) * (opts.width_fraction or 1)))
	local rows = math.max(1, math.floor((tonumber(opts.rows) or 20) * (opts.height_fraction or 1)))
	local styles = opts.styles or {}
	local function style(key)
		return styles[key] or ""
	end
	local function paint(value, key)
		return style(key) .. value .. style("text") .. style("normal")
	end
	local data = opts.menu or menu(opts)
	local items = {}
	for _, item in ipairs(data) do
		items[#items + 1] = {
			key = "[" .. item[1] .. "]",
			desc = item[2],
			group = item.group == true,
			critical = item.critical == true,
		}
	end
	if #items == 0 then
		items[1] = { key = "", desc = "No entries" }
	end
	local ellipsis = opts.ascii and "." or "…"
	local t = Layout.new({
		cols = { { key = "key", hl = "key", align = "right", padding = { 0, 1 } }, { key = "desc", width = math.huge } },
		rows = items,
		ellipsis = ellipsis,
	})
	local padding = cols >= 8 and 2 or 0
	local available = math.max(1, (opts.full_width and cols or math.min(cols, 60)) - padding * 2)
	local _, _, max_row_width = t:cells()
	local box_width = Layout.dim(max_row_width, available, { min = 20 })
	local columns = math.max(1, math.min(opts.full_width and #items or 2, math.floor(available / (box_width + 3))))
	local desired_rows = math.ceil(#items / columns) + 4
	local row_limit = opts.full_width and math.max(1, rows - 4) or math.min(6, math.max(1, rows - 4))
	local box_height = math.max(1, math.min(row_limit, math.ceil(#items / columns)))
	if opts.full_width then
		columns = math.min(columns, math.ceil(#items / box_height))
	end
	local capacity = box_height * columns
	local pages = math.max(1, math.ceil(#items / capacity))
	local page = math.max(0, math.floor(tonumber(opts.page) or 0)) % pages
	box_width = math.max(1, math.floor((available - (columns - 1) * 3) / columns))
	local laid = t:layout({ width = box_width })
	local contents = {}
	local function append(plain, colored)
		contents[#contents + 1] = { plain = plain, colored = colored or plain }
	end
	local function label(value)
		value = Text.clean(value)
		return Text.fit(
			value,
			opts.full_width and available or math.min(available, Text.width(value)),
			opts.full_width and "center" or "left",
			ellipsis
		)
	end
	local title = label(data.title)
	append(title, paint(title, "title"))
	local rule = string.rep(opts.ascii and "-" or "─", opts.full_width and available or math.min(available, 40))
	append(rule, paint(rule, "border"))
	for row = 1, box_height do
		local plain, colored = {}, {}
		for column = 1, columns do
			local i = page * capacity + (column - 1) * box_height + row
			if column > 1 then
				plain[#plain + 1], colored[#colored + 1] = "   ", "   "
			end
			local used = 0
			for c, cell in ipairs(laid[i] or {}) do
				used = used + Text.width(cell.value)
				plain[#plain + 1] = cell.value
				local hl = c == 1 and "key"
					or (items[i].critical and "critical" or (items[i].group and "group" or "text"))
				colored[#colored + 1] = paint(cell.value, hl)
			end
			if opts.full_width then
				local gap = string.rep(" ", box_width - used)
				plain[#plain + 1], colored[#colored + 1] = gap, gap
			end
		end
		append(table.concat(plain), table.concat(colored))
	end
	append("")
	local root = opts.prefix == nil or opts.prefix == ""
	local quit_with_q = data.quit_with_q ~= false
	local help = root and (quit_with_q and "Esc/q close" or "Esc close")
		or (quit_with_q and "Esc/Bksp back   q close" or "Esc/Bksp back")
	if opts.confirmation and opts.confirmation ~= "" then
		help = "y confirm   Esc/n cancel"
	elseif opts.notice and opts.notice ~= "" then
		help = "Esc/q close"
	end
	if pages > 1 then
		local paging = "  Tab page " .. (page + 1) .. "/" .. pages
		if Text.width(help .. paging) > available then
			help = help:gsub("/Bksp", "")
			paging = "  Tab " .. (page + 1) .. "/" .. pages
		end
		help = help .. paging
	end
	if opts.notice and opts.notice ~= "" then
		help = help .. "   " .. Text.clean(opts.notice)
	end
	help = label(help)
	append(help, paint(help, "muted"))
	local content_width = 0
	for _, line in ipairs(contents) do
		content_width = math.max(content_width, Text.width(line.plain))
	end
	local width = math.min(cols, content_width + padding * 2)
	local margin = math.floor((cols - width) / 2)
	local lines = {}
	for i = 1, math.min(rows, #contents) do
		local line = contents[i]
		lines[#lines + 1] = string.rep(" ", margin + padding)
			.. line.colored
			.. string.rep(" ", content_width - Text.width(line.plain) + padding)
	end
	return {
		lines = lines,
		page = page,
		pages = pages,
		columns = columns,
		cols = cols,
		rows = rows,
		desired_rows = desired_rows,
		margin = margin,
		width = width,
	}
end

return M
