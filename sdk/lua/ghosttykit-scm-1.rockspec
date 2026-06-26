---@diagnostic disable: lowercase-global

rockspec_format = "3.0"
package = "ghosttykit"
version = "scm-1"
source = {
  url = "git://github.com/thurstonsand/ghosttykit",
}
description = {
  summary = "Lua SDK for GhosttyKit daemon clients",
  homepage = "https://github.com/thurstonsand/ghosttykit",
  license = "MIT",
}
dependencies = {
  "lua >= 5.1",
  "luv >= 1.51.0",
  "dkjson >= 2.8",
}
test_dependencies = {
  "busted >= 2.2.0",
  "luacheck >= 1.2.0",
}
build = {
  type = "builtin",
  modules = {
    ["ghosttykit"] = "lua/ghosttykit/init.lua",
    ["ghosttykit.client.bridge"] = "lua/ghosttykit/client/bridge.lua",
    ["ghosttykit.client.key_table"] = "lua/ghosttykit/client/key_table.lua",
    ["ghosttykit.client.layout"] = "lua/ghosttykit/client/layout.lua",
    ["ghosttykit.client.paste"] = "lua/ghosttykit/client/paste.lua",
    ["ghosttykit.client.raw"] = "lua/ghosttykit/client/raw.lua",
    ["ghosttykit.client.terminal"] = "lua/ghosttykit/client/terminal.lua",
    ["ghosttykit.error"] = "lua/ghosttykit/error.lua",
    ["ghosttykit.json"] = "lua/ghosttykit/json.lua",
    ["ghosttykit.protocol"] = "lua/ghosttykit/protocol.lua",
    ["ghosttykit.socket"] = "lua/ghosttykit/socket.lua",
    ["ghosttykit.transport"] = "lua/ghosttykit/transport.lua",
    ["ghosttykit.transport_luv"] = "lua/ghosttykit/transport_luv.lua",
    ["ghosttykit.transport_nvim"] = "lua/ghosttykit/transport_nvim.lua",
    ["ghosttykit.uv_transport"] = "lua/ghosttykit/uv_transport.lua",
  },
}
