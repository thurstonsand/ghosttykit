local uv = require("luv")
local json = require("ghosttykit.json").auto()
local uv_transport = require("ghosttykit.uv_transport")

local function run_once()
  uv.run("once")
end

return uv_transport.new(uv, json, run_once)
