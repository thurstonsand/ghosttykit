local protocol = require("ghosttykit.protocol")
local errors = require("ghosttykit.error")
local json = require("ghosttykit.json")
local socket = require("ghosttykit.socket")

---@class ghosttykit.Request: table
---@field version integer
---@field command string

---@class ghosttykit.Json
---@field encode fun(value: table): string
---@field decode fun(value: string): table

---@class ghosttykit.Transport
---@field request fun(self: ghosttykit.Transport, socket_path: string, payload: string, mode: string): table?, string?

---@class ghosttykit.StreamResult
---@field header table
---@field body string

---@class ghosttykit.HoldResult
---@field reply table
---@field close fun()

---@class ghosttykit
---@field protocol_version integer
---@field codes table<string,string>
---@field protocol ghosttykit.protocol
local M = {
  protocol_version = protocol.version,
  codes = protocol.codes,
  protocol = protocol,
}

---@class ghosttykit.Client
---@field socket_path string
---@field transport ghosttykit.Transport
---@field json ghosttykit.Json
local Client = {}
Client.__index = Client

local function validate_mode(request, want)
  local got = protocol.reply_mode_of(request)
  if got == want then
    return nil
  end
  return errors.new("invalid_reply_mode", "request reply mode is " .. got .. ", not " .. want)
end

local function request(client, req, mode)
  local err = validate_mode(req, mode)
  if err then
    return nil, err
  end

  local payload = protocol.encode_request(req, client.json)
  local result, transport_err = client.transport:request(client.socket_path, payload, mode)
  if transport_err then
    return nil, errors.new("transport_error", transport_err)
  end

  if mode == protocol.reply_mode.none then
    return true, nil
  end

  if mode == protocol.reply_mode.stream then
    err = errors.from_reply(result.header)
    if err then
      return nil, err
    end
    return result, nil
  end

  if mode == protocol.reply_mode.hold then
    err = errors.from_reply(result.reply)
    if err then
      result.close()
      return nil, err
    end
    return result, nil
  end

  err = errors.from_reply(result)
  if err then
    return nil, err
  end
  return result, nil
end

---@param req ghosttykit.Request
---@return any reply
---@return ghosttykit.Error? err
function Client:call(req)
  return request(self, req, protocol.reply_mode.frame)
end

---@param req ghosttykit.Request
---@return boolean|nil ok
---@return ghosttykit.Error? err
function Client:notify(req)
  return request(self, req, protocol.reply_mode.none)
end

---@param req ghosttykit.Request
---@return any result
---@return ghosttykit.Error? err
function Client:stream(req)
  return request(self, req, protocol.reply_mode.stream)
end

---@param req ghosttykit.Request
---@return any result
---@return ghosttykit.Error? err
function Client:hold(req)
  return request(self, req, protocol.reply_mode.hold)
end

function Client:notify_ack(req, ack)
  if ack then
    local _, err = self:call(req)
    return err == nil, err
  end
  return self:notify(req)
end

function Client:doctor()
  return self:call(protocol.doctor())
end

function Client:terminal_id(opts)
  return self:call(protocol.terminal_id(opts))
end

function Client:tab_terminal_count(opts)
  return self:call(protocol.tab_terminal_count(opts))
end

function Client:key_table_activate(opts)
  opts = opts or {}
  return self:notify_ack(protocol.key_table_activate(opts), opts.ack)
end

function Client:key_table_deactivate(opts)
  opts = opts or {}
  return self:notify_ack(protocol.key_table_deactivate(opts), opts.ack)
end

function Client:focus(opts)
  opts = opts or {}
  return self:notify_ack(protocol.focus(opts), opts.ack)
end

function Client:split(opts)
  opts = opts or {}
  return self:notify_ack(protocol.split(opts), opts.ack)
end

function Client:resize(opts)
  opts = opts or {}
  return self:notify_ack(protocol.resize(opts), opts.ack)
end

function Client:zoom(opts)
  opts = opts or {}
  return self:notify_ack(protocol.zoom(opts), opts.ack)
end

function Client:paste(opts)
  return self:stream(protocol.paste(opts))
end

function Client:bridge_create(opts)
  return self:call(protocol.bridge_create(opts))
end

function Client:bridge_lease(token)
  return self:hold(protocol.bridge_lease(token))
end

---@class ghosttykit.ClientOptions
---@field socket_path string?
---@field transport ghosttykit.Transport?
---@field json ghosttykit.Json?

---@param opts ghosttykit.ClientOptions?
---@return ghosttykit.Client
function M.client(opts)
  opts = opts or {}
  return setmetatable({
    socket_path = opts.socket_path or socket.path(),
    transport = opts.transport or require("ghosttykit.transport").auto(),
    json = opts.json or json.auto(),
  }, Client)
end

M.new = M.client
M.Client = Client

return M
