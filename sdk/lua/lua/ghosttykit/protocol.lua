---@class ghosttykit.protocol
local M = {}

M.version = 1

M.codes = {
  ok = "ok",
  protocol_version_mismatch = "protocol_version_mismatch",
  unknown_command = "unknown_command",
  invalid_request = "invalid_request",
  terminal_not_found = "terminal_not_found",
  ghostty_unavailable = "ghostty_unavailable",
  paste_empty = "paste_empty",
  paste_unsupported = "paste_unsupported",
  stream_failed = "stream_failed",
  internal_error = "internal_error",
}

M.reply_mode = {
  frame = "frame",
  none = "none",
  stream = "stream",
  hold = "hold",
}

local function envelope(command)
  return { version = M.version, command = command }
end

local function ack_mode(ack)
  if ack then
    return M.reply_mode.frame
  end
  return M.reply_mode.none
end

function M.reply_mode_of(request)
  return request._reply_mode or M.reply_mode.frame
end

function M.encode_request(request, json)
  local copy = {}
  for key, value in pairs(request) do
    if key ~= "_reply_mode" then
      copy[key] = value
    end
  end
  return json.encode(copy) .. "\n"
end

function M.doctor()
  return envelope("doctor")
end

function M.terminal_id(opts)
  opts = opts or {}
  local request = envelope("terminal-id")
  request.tty = opts.tty
  request.focused = opts.focused or nil
  request.refresh = opts.refresh or nil
  return request
end

function M.tab_terminal_count(opts)
  opts = opts or {}
  local request = envelope("tab-terminal-count")
  request.tty = opts.tty
  request.focused = opts.focused or nil
  return request
end

function M.bridge_create(opts)
  opts = opts or {}
  local request = envelope("bridge-create")
  request.tty = opts.tty
  request.focused = opts.focused or nil
  return request
end

function M.bridge_lease(token)
  local request = envelope("bridge-lease")
  request.token = token
  request._reply_mode = M.reply_mode.hold
  return request
end

function M.clear_cache(opts)
  opts = opts or {}
  local request = envelope("clear-cache")
  request.tty = opts.tty
  request.ack = opts.ack or nil
  request._reply_mode = ack_mode(opts.ack)
  return request
end

---@class ghosttykit.KeyTableActivateOptions
---@field tty string?
---@field focused boolean?
---@field table string
---@field ack boolean?

---@param opts ghosttykit.KeyTableActivateOptions
---@return ghosttykit.Request
function M.key_table_activate(opts)
  opts = opts or {}
  local request = envelope("key-table-activate")
  request.tty = opts.tty
  request.focused = opts.focused or nil
  request.table = opts.table
  request.ack = opts.ack or nil
  request._reply_mode = ack_mode(opts.ack)
  return request
end

---@class ghosttykit.KeyTableDeactivateOptions
---@field tty string?
---@field focused boolean?
---@field ack boolean?

---@param opts ghosttykit.KeyTableDeactivateOptions
---@return ghosttykit.Request
function M.key_table_deactivate(opts)
  opts = opts or {}
  local request = envelope("key-table-deactivate")
  request.tty = opts.tty
  request.focused = opts.focused or nil
  request.ack = opts.ack or nil
  request._reply_mode = ack_mode(opts.ack)
  return request
end

---@class ghosttykit.FocusOptions
---@field tty string?
---@field focused boolean?
---@field direction "left"|"down"|"up"|"right"
---@field ack boolean?

---@param opts ghosttykit.FocusOptions
---@return ghosttykit.Request
function M.focus(opts)
  opts = opts or {}
  local request = envelope("focus")
  request.tty = opts.tty
  request.focused = opts.focused or nil
  request.direction = opts.direction
  request.ack = opts.ack or nil
  request._reply_mode = ack_mode(opts.ack)
  return request
end

function M.split(opts)
  opts = opts or {}
  local request = envelope("split")
  request.tty = opts.tty
  request.focused = opts.focused or nil
  request.direction = opts.direction
  request.cwd = opts.cwd
  request.commandText = opts.command_text
  request.focus = opts.focus
  request.ack = opts.ack or nil
  request._reply_mode = ack_mode(opts.ack)
  return request
end

function M.resize(opts)
  opts = opts or {}
  local request = envelope("resize")
  request.tty = opts.tty
  request.focused = opts.focused or nil
  request.direction = opts.direction
  request.amount = opts.amount
  request.ack = opts.ack or nil
  request._reply_mode = ack_mode(opts.ack)
  return request
end

function M.zoom(opts)
  opts = opts or {}
  local request = envelope("zoom")
  request.tty = opts.tty
  request.focused = opts.focused or nil
  request.ack = opts.ack or nil
  request._reply_mode = ack_mode(opts.ack)
  return request
end

function M.paste(opts)
  opts = opts or {}
  local request = envelope("paste")
  request.tty = opts.tty
  request._reply_mode = M.reply_mode.stream
  return request
end

return M
