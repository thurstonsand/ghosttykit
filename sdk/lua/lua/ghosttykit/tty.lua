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

--- Resolves a request target as `tty, caller_tty`. An explicit value, or else GTY_TTY, is the
--- explicit `tty`. Otherwise the caller's own terminal is `caller`, when the caller knows it, or
--- the process's controlling terminal. A process with no terminal names none: whether its
--- endpoint needs one is the daemon's decision.
---@param explicit string?
---@param caller string?
---@return string? tty
---@return string? caller_tty
function M.resolve(explicit, caller)
  if not explicit or explicit == "" then
    explicit = os.getenv("GTY_TTY")
  end
  if explicit and explicit ~= "" then
    return M.normalize(explicit), nil
  end
  if caller and caller ~= "" then
    return nil, M.normalize(caller)
  end
  if derived == nil then
    derived = current() or false
  end
  return nil, derived or nil
end

return M
