local protocol = require("ghosttykit.protocol")
local errors = require("ghosttykit.error")

local M = {}

local Terminal = {}
Terminal.__index = Terminal

local function reply_value(reply, message)
  if reply and reply.value ~= nil and reply.value ~= "" then
    return reply.value, nil
  end
  return nil, errors.new("invalid_reply", message)
end

function Terminal:id(opts)
  local reply, err = self.ops.call(self.client, protocol.terminal_id(opts))
  if err then
    return nil, err
  end
  return reply_value(reply, "terminal-id reply missing terminal ID")
end

function Terminal:count(opts)
  local reply, err = self.ops.call(self.client, protocol.tab_terminal_count(opts))
  if err then
    return nil, err
  end

  local value
  value, err = reply_value(reply, "tab-terminal-count reply missing count")
  if err then
    return nil, err
  end

  local count = tonumber(value)
  if count == nil then
    return nil, errors.new("invalid_reply", "tab-terminal-count reply has invalid count")
  end
  return count, nil
end

function Terminal:clear_cache(opts)
  opts = opts or {}
  return self.ops.notify_ack(self.client, protocol.clear_cache(opts), opts.ack)
end

---Sends text as bracketed paste, leaving it in the line editor unless submit is true.
---Bridge sockets target their bound terminal.
function Terminal:input(opts)
  opts = opts or {}
  return self.ops.notify_ack(self.client, protocol.input(opts), opts.ack)
end

function M.new(client, ops)
  return setmetatable({ client = client, ops = ops }, Terminal)
end

return M
