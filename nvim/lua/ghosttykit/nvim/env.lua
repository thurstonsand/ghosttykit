local M = {}

function M.in_ghostty()
  if vim.env.TERM_PROGRAM == "ghostty" then
    return true
  end

  for _, ui in ipairs(vim.api.nvim_list_uis()) do
    if tostring(ui.term_name or ""):find("ghostty", 1, true) then
      return true
    end
  end

  return false
end

function M.has_bridge()
  return vim.env.GTY_SOCK ~= nil and vim.env.GTY_SOCK ~= ""
end

function M.available_context()
  return M.in_ghostty() or M.has_bridge()
end

return M
