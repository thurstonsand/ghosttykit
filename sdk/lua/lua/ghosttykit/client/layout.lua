local protocol = require("ghosttykit.protocol")

local M = {}

local Layout = {}
Layout.__index = Layout

local function request_options(opts)
  local request_opts = {}
  for key, value in pairs(opts or {}) do
    request_opts[key] = value
  end
  return request_opts
end

local function resize_options(opts)
  local request_opts = request_options(opts)
  if request_opts.amount == nil then
    if request_opts.pixels ~= nil then
      request_opts.amount = { pixels = request_opts.pixels }
    elseif request_opts.percent ~= nil then
      request_opts.amount = { percent = request_opts.percent }
    end
  end
  request_opts.pixels = nil
  request_opts.percent = nil
  return request_opts
end

function Layout:focus(opts)
  opts = opts or {}
  return self.ops.notify_ack(self.client, protocol.focus(opts), opts.ack)
end

function Layout:split(opts)
  opts = opts or {}
  return self.ops.notify_ack(self.client, protocol.split(opts), opts.ack)
end

function Layout:resize(opts)
  opts = opts or {}
  return self.ops.notify_ack(self.client, protocol.resize(resize_options(opts)), opts.ack)
end

function Layout:zoom(opts)
  opts = opts or {}
  return self.ops.notify_ack(self.client, protocol.zoom(opts), opts.ack)
end

function M.new(client, ops)
  return setmetatable({ client = client, ops = ops }, Layout)
end

return M
