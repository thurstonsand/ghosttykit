local client = require("ghosttykit.nvim.client")
local env = require("ghosttykit.nvim.env")

local M = {}

local health = vim.health or require("health")

local function start(name)
  if health.start then
    health.start(name)
  else
    health.report_start(name)
  end
end

local function ok(message)
  if health.ok then
    health.ok(message)
  else
    health.report_ok(message)
  end
end

local function warn(message)
  if health.warn then
    health.warn(message)
  else
    health.report_warn(message)
  end
end

local function error_report(message)
  if health.error then
    health.error(message)
  else
    health.report_error(message)
  end
end

function M.check()
  start("ghosttykit")

  if env.in_ghostty() then
    ok("Ghostty UI detected")
  elseif env.has_bridge() then
    ok("GTY_SOCK bridge detected")
  else
    warn("No Ghostty UI or GTY_SOCK bridge detected")
  end

  local reply, err = client.doctor()
  if err then
    error_report("doctor failed: " .. tostring(err))
    return
  end

  if reply.healthy then
    ok("daemon doctor reports healthy")
  else
    warn("daemon doctor reports failed checks")
  end

  for _, check in ipairs(reply.checks or {}) do
    local message = check.name
    if check.message and check.message ~= "" then
      message = message .. ": " .. check.message
    end
    if check.status == "ok" then
      ok(message)
    elseif check.status == "warn" then
      warn(message)
    else
      error_report(message)
    end
  end
end

return M
