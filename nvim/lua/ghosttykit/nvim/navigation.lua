local client = require("ghosttykit.nvim.client")
local config = require("ghosttykit.nvim.config")

local M = {}

local directions = {
  left = "h",
  down = "j",
  up = "k",
  right = "l",
}

local function is_floating_window(win)
  local cfg = vim.api.nvim_win_get_config(win or 0)
  return cfg and cfg.relative ~= ""
end

local function is_embedded_floating_window(win)
  if not is_floating_window(win) then
    return false
  end

  local cfg = vim.api.nvim_win_get_config(win or 0)
  return cfg.zindex ~= nil and cfg.zindex < 50
end

local function is_floating_window_at_screen_edge(win, dir)
  win = win or vim.api.nvim_get_current_win()
  if not is_floating_window(win) then
    return false
  end

  local cfg = vim.api.nvim_win_get_config(win)
  local col = type(cfg.col) == "number" and cfg.col or 0
  local row = type(cfg.row) == "number" and cfg.row or 0

  if dir == "left" then
    return col <= 0
  elseif dir == "right" then
    return col + cfg.width >= vim.o.columns
  elseif dir == "up" then
    return row <= 0
  elseif dir == "down" then
    return row + cfg.height >= vim.o.lines - vim.o.cmdheight
  end

  return false
end

local function handle_floating_window(mux_callback)
  if not is_floating_window() then
    return false
  end

  if config.get().float_win_behavior == "previous" then
    local prev_win = vim.fn.win_getid(vim.fn.winnr("#"))
    if prev_win == 0 or not vim.api.nvim_win_is_valid(prev_win) or is_floating_window(prev_win) then
      return true
    end
    vim.api.nvim_set_current_win(prev_win)
    return false
  elseif config.get().float_win_behavior == "mux" then
    mux_callback()
    return true
  end

  return false
end

function M.navigate(direction)
  local wincmd = directions[direction]
  if not wincmd then
    error("unknown direction: " .. tostring(direction))
  end

  if is_embedded_floating_window() then
    if is_floating_window_at_screen_edge(nil, direction) then
      return client.focus(direction)
    end

    vim.cmd("wincmd " .. wincmd)
    return true, nil
  end

  if handle_floating_window(function()
    return client.focus(direction)
  end) then
    return true, nil
  end

  local current_winnr = vim.fn.winnr()
  local target_winnr = vim.fn.winnr(wincmd)

  if target_winnr == current_winnr then
    return client.focus(direction)
  end

  local target_win = vim.fn.win_getid(target_winnr)
  if target_win ~= 0 and vim.api.nvim_win_is_valid(target_win) then
    vim.api.nvim_set_current_win(target_win)
    return true, nil
  end

  return client.focus(direction)
end

return M
