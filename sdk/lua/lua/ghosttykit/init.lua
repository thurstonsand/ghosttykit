local protocol = require("ghosttykit.protocol")
local errors = require("ghosttykit.error")
local json = require("ghosttykit.json")
local socket = require("ghosttykit.socket")
local tty = require("ghosttykit.tty")

---@class ghosttykit.Request: table
---@field version integer
---@field command string

---@class ghosttykit.Json
---@field encode fun(value: table): string
---@field decode fun(value: string): table

---@class ghosttykit.Transport
---@field request fun(self: ghosttykit.Transport, socket_path: string, payload: string, mode: string): table?, string?

---@class ghosttykit.StreamBody
---@field read fun(self: ghosttykit.StreamBody): string?, string?
---@field read_all fun(self: ghosttykit.StreamBody): string?, string?
---@field close fun(self: ghosttykit.StreamBody)

---@class ghosttykit.StreamResult
---@field header table
---@field body ghosttykit.StreamBody

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
---@field raw table
---@field terminal table
---@field key_table table
---@field layout table
---@field paste table
---@field bridge table
local Client = {}
Client.__index = Client

local function validate_mode(req, want)
  local got = protocol.reply_mode_of(req)
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

local function call(client, req)
  return request(client, req, protocol.reply_mode.frame)
end

local function notify(client, req)
  return request(client, req, protocol.reply_mode.none)
end

local function stream(client, req)
  return request(client, req, protocol.reply_mode.stream)
end

local function hold(client, req)
  return request(client, req, protocol.reply_mode.hold)
end

local function notify_ack(client, req, ack)
  if ack then
    local _, err = call(client, req)
    return err == nil, err
  end
  return notify(client, req)
end

local function resolve_terminal_options(opts)
  opts = opts or {}
  local resolved = tty.resolve(opts.tty)
  if not resolved then
    return nil, errors.new("invalid_request", "no tty: pass tty explicitly or set GTY_TTY")
  end
  local result = {}
  for key, value in pairs(opts) do
    result[key] = value
  end
  result.tty = resolved
  return result, nil
end

local ops = {
  call = call,
  notify = notify,
  stream = stream,
  hold = hold,
  notify_ack = notify_ack,
  resolve_terminal_options = resolve_terminal_options,
}

function Client:doctor()
  local reply, err = call(self, protocol.doctor())
  if err then
    return nil, err
  end
  if not reply then
    return nil, errors.new("invalid_reply", "empty doctor reply")
  end
  return {
    healthy = reply.healthy == true,
    checks = reply.checks or {},
  }, nil
end

local domains = {
  raw = require("ghosttykit.client.raw"),
  terminal = require("ghosttykit.client.terminal"),
  key_table = require("ghosttykit.client.key_table"),
  layout = require("ghosttykit.client.layout"),
  paste = require("ghosttykit.client.paste"),
  bridge = require("ghosttykit.client.bridge"),
}

local function attach_domains(client)
  ops.new_client = M.client
  for name, domain in pairs(domains) do
    client[name] = domain.new(client, ops)
  end
end

---@class ghosttykit.ClientOptions
---@field socket_path string?
---@field transport ghosttykit.Transport?
---@field json ghosttykit.Json?

---@param opts ghosttykit.ClientOptions?
---@return ghosttykit.Client
function M.client(opts)
  opts = opts or {}
  local client = setmetatable({
    socket_path = opts.socket_path or socket.path(),
    transport = opts.transport or require("ghosttykit.transport").auto(),
    json = opts.json or json.auto(),
  }, Client)
  attach_domains(client)
  return client
end

M.new = M.client
M.Client = Client

return M
