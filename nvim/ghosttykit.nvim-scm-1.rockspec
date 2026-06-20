---@diagnostic disable: lowercase-global

rockspec_format = "3.0"
package = "ghosttykit.nvim"
version = "scm-1"
source = {
  url = "git://github.com/thurstonsand/ghosttykit",
}
description = {
  summary = "Neovim integration for GhosttyKit",
  homepage = "https://github.com/thurstonsand/ghosttykit",
  license = "MIT",
}
dependencies = {
  "lua >= 5.1",
  "ghosttykit == scm-1",
}
test_dependencies = {
  "busted >= 2.2.0",
  "luacheck >= 1.2.0",
}
build = {
  type = "builtin",
  modules = {
    ["ghosttykit.health"] = "lua/ghosttykit/health.lua",
    ["ghosttykit.nvim"] = "lua/ghosttykit/nvim.lua",
    ["ghosttykit.nvim.client"] = "lua/ghosttykit/nvim/client.lua",
    ["ghosttykit.nvim.config"] = "lua/ghosttykit/nvim/config.lua",
    ["ghosttykit.nvim.env"] = "lua/ghosttykit/nvim/env.lua",
    ["ghosttykit.nvim.health"] = "lua/ghosttykit/nvim/health.lua",
    ["ghosttykit.nvim.keymaps"] = "lua/ghosttykit/nvim/keymaps.lua",
    ["ghosttykit.nvim.navigation"] = "lua/ghosttykit/nvim/navigation.lua",
    ["ghosttykit.nvim.tty"] = "lua/ghosttykit/nvim/tty.lua",
  },
  install = {
    conf = {
      ["plugin/ghosttykit.lua"] = "plugin/ghosttykit.lua",
      ["doc/ghosttykit.txt"] = "doc/ghosttykit.txt",
    },
  },
}
