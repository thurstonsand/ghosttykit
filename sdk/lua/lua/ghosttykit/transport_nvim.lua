local uv_transport = require("ghosttykit.uv_transport")
local vim_runtime = assert(rawget(_G, "vim"), "ghosttykit nvim transport requires vim")

local function run_once()
  vim_runtime.uv.run("once")
end

return uv_transport.new(vim_runtime.uv, vim_runtime.json, run_once)
