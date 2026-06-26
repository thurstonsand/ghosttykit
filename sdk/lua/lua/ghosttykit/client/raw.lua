local M = {}

local Raw = {}
Raw.__index = Raw

function Raw:call(req)
  return self.ops.call(self.client, req)
end

function Raw:notify(req)
  return self.ops.notify(self.client, req)
end

function Raw:stream(req)
  return self.ops.stream(self.client, req)
end

function Raw:hold(req)
  return self.ops.hold(self.client, req)
end

function M.new(client, ops)
  return setmetatable({ client = client, ops = ops }, Raw)
end

return M
