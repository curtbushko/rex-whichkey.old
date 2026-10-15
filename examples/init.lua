-- Merge this into your existing Rex init.lua after installing the HM module.
local config_home = os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")
local whichkey = dofile(config_home .. "/rex/whichkey/plugin.lua")
whichkey.setup({ position = "center" })
rex.bind("alt+space", "whichkey")
rex.bind("ctrl+b>space", "whichkey")
