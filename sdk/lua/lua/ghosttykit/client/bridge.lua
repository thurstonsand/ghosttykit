local protocol = require("ghosttykit.protocol")
local errors = require("ghosttykit.error")

local M = {}

local BridgeClient = {}
BridgeClient.__index = BridgeClient

local Bridge = {}
Bridge.__index = Bridge

function BridgeClient:create(opts)
  local reply, err = self.ops.call(self.client, protocol.bridge_create(opts))
  if err then
    return nil, err
  end
  if not reply then
    return nil, errors.new("invalid_reply", "empty bridge-create reply")
  end

  local socket_path = reply.socketPath
  local lease_token = reply.leaseToken
  if not socket_path or not lease_token then
    return nil, errors.new("invalid_reply", "bridge-create reply missing socket path or lease token")
  end

  local lease_client = self.ops.new_client({
    socket_path = socket_path,
    transport = self.client.transport,
    json = self.client.json,
  })
  local lease
  lease, err = self.ops.hold(lease_client, protocol.bridge_lease(lease_token))
  if err then
    return nil, err
  end

  return setmetatable({
    socket_path = socket_path,
    lease = lease,
  }, Bridge), nil
end

function Bridge:close()
  self.lease.close()
end

function M.new(client, ops)
  return setmetatable({ client = client, ops = ops }, BridgeClient)
end

return M
