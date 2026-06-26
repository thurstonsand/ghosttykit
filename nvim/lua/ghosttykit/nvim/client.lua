local ghosttykit = require("ghosttykit")
local config = require("ghosttykit.nvim.config")
local tty = require("ghosttykit.nvim.tty")

local M = {}

local function target()
  return {
    tty = tty.current(),
    focused = config.get().focused,
  }
end

local function notify(err)
  if err and config.get().notify_errors then
    vim.notify(tostring(err), vim.log.levels.WARN, { title = "ghosttykit" })
  end
end

function M.sdk()
  return ghosttykit.client()
end

function M.activate_key_table()
  local opts = target()
  opts.name = config.get().key_table
  opts.ack = false
  local ok, err = M.sdk().key_table:activate(opts)
  notify(err)
  return ok, err
end

function M.deactivate_key_table()
  local opts = target()
  opts.ack = false
  local ok, err = M.sdk().key_table:deactivate(opts)
  notify(err)
  return ok, err
end

function M.focus(direction)
  local opts = target()
  opts.direction = direction
  opts.ack = false
  local ok, err = M.sdk().layout:focus(opts)
  notify(err)
  return ok, err
end

function M.doctor()
  return M.sdk():doctor()
end

return M
