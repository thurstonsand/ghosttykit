local M = {}

local cached_tty = nil

local function tui_pid()
  for _, ui in ipairs(vim.api.nvim_list_uis()) do
    local ok, info = pcall(vim.api.nvim_get_chan_info, ui.chan)
    local client = ok and info.client or nil
    local attrs = client and client.attributes or nil
    local pid = attrs and tonumber(attrs.pid) or nil
    if client and client.name == "nvim-tui" and pid then
      return pid
    end
  end
  return nil
end

local function tty_for_pid(pid)
  local result = vim.system({ "ps", "-p", tostring(pid), "-o", "tty=" }, { text = true }):wait()
  if result.code ~= 0 then
    return nil
  end

  local tty = vim.trim(result.stdout or "")
  if tty == "" or tty == "?" or tty == "??" then
    return nil
  end

  if not tty:match("^/") then
    tty = "/dev/" .. tty
  end

  return tty
end

function M.current()
  if cached_tty then
    return cached_tty
  end

  if vim.env.GTY_TTY and vim.env.GTY_TTY ~= "" then
    cached_tty = vim.env.GTY_TTY
    return cached_tty
  end

  local pid = tui_pid()
  if not pid then
    return nil
  end

  cached_tty = tty_for_pid(pid)
  return cached_tty
end

function M.reset()
  cached_tty = nil
end

return M
