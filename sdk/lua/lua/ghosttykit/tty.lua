local M = {}

local derived = nil

function M.normalize(value)
  if value:sub(1, 5) == "/dev/" then
    return value
  end
  return "/dev/" .. value
end

local function current()
  local handle = io.popen("tty 2>/dev/null")
  if not handle then
    return nil
  end
  local output = handle:read("*l") or ""
  handle:close()
  if output == "" or output == "not a tty" then
    return nil
  end
  return M.normalize(output)
end

--- Normalizes an explicit tty value, or derives the caller's: GTY_TTY first, then the process's
--- controlling terminal. The daemon requires a tty on every terminal-targeted request; when
--- nothing is derivable this returns nil and the daemon reports the missing field.
---@param value string?
---@return string?
function M.resolve(value)
  if value and value ~= "" then
    return M.normalize(value)
  end
  local env = os.getenv("GTY_TTY")
  if env and env ~= "" then
    return M.normalize(env)
  end
  if derived == nil then
    derived = current() or false
  end
  return derived or nil
end

return M
