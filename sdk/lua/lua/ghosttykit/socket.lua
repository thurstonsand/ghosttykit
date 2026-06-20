local M = {}

local function dirname(path)
  return path:match("^(.*)/[^/]*$") or "."
end

local function default_home()
  return os.getenv("HOME") or ""
end

function M.path()
  local override = os.getenv("GTY_SOCK")
  if override and override ~= "" then
    return override
  end
  local home = default_home()
  if home == "" then
    return ""
  end
  return home .. "/.local/run/ghosttykit/ghosttykitd.sock"
end

function M.parent_dir(path)
  return dirname(path)
end

return M
