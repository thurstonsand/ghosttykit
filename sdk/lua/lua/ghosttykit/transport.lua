local M = {}

function M.auto()
  local vim_runtime = rawget(_G, "vim")
  if vim_runtime and vim_runtime.uv and vim_runtime.json then
    return require("ghosttykit.transport_nvim")
  end
  return require("ghosttykit.transport_luv")
end

return M
