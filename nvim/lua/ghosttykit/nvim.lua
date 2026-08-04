local config = require("ghosttykit.nvim.config")
local env = require("ghosttykit.nvim.env")
local keymaps = require("ghosttykit.nvim.keymaps")
local navigation = require("ghosttykit.nvim.navigation")
local client = require("ghosttykit.nvim.client")

local M = {}
local setup_done = false

local function setup_autocmds()
  if not env.available_context() then
    return false
  end

  local group = vim.api.nvim_create_augroup("ghosttykit", { clear = true })

  vim.api.nvim_create_autocmd({ "VimEnter", "VimResume", "FocusGained" }, {
    group = group,
    callback = function()
      client.activate_key_table()
    end,
  })

  vim.api.nvim_create_autocmd({ "VimSuspend", "VimLeavePre" }, {
    group = group,
    callback = function()
      client.deactivate_key_table()
    end,
  })

  return true
end

function M.setup(opts)
  config.setup(opts)
  keymaps.setup_plug_mappings()

  if setup_done then
    return
  end
  setup_done = true

  -- Inside Herdr, `gty herdr attach` owns the Ghostty key table for the whole session. Neovim
  -- exiting or suspending must not take those keys back from the Herdr panes around it.
  if env.in_herdr() then
    return
  end

  if setup_autocmds() then
    client.activate_key_table()
  end
end

function M.navigate(direction)
  return navigation.navigate(direction)
end

function M.doctor()
  return client.doctor()
end

return M
