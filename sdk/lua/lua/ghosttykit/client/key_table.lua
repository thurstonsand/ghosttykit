local protocol = require("ghosttykit.protocol")

local M = {}

local KeyTable = {}
KeyTable.__index = KeyTable

local function request_options(opts)
  local request_opts = {}
  for key, value in pairs(opts or {}) do
    request_opts[key] = value
  end
  request_opts.table = request_opts.name
  request_opts.name = nil
  return request_opts
end

function KeyTable:activate(opts)
  local err
  opts, err = self.ops.resolve_terminal_options(opts)
  if err then
    return nil, err
  end
  return self.ops.notify_ack(self.client, protocol.key_table_activate(request_options(opts)), opts.ack)
end

function KeyTable:deactivate(opts)
  local err
  opts, err = self.ops.resolve_terminal_options(opts)
  if err then
    return nil, err
  end
  return self.ops.notify_ack(self.client, protocol.key_table_deactivate(opts), opts.ack)
end

function M.new(client, ops)
  return setmetatable({ client = client, ops = ops }, KeyTable)
end

return M
