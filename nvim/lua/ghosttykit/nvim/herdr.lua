local config = require("ghosttykit.nvim.config")

local M = {}

-- Counterpart to osc.NavigationTitle in cli/gty/internal/osc/filter.go, which recognizes this
-- exact title in the SSH stream. The two spellings must stay in sync.
local navigation_sentinel_prefix = "gty-nav:v1:"

local request_counter = 0
local request_timeout_ms = 2000

local function notify(err)
  if err and config.get().notify_errors then
    vim.notify(tostring(err), vim.log.levels.WARN, { title = "ghosttykit" })
  end
end

-- Herdr sends JSON null for an absent pane, which vim.json decodes to vim.NIL.
local function present(value)
  return value ~= nil and value ~= vim.NIL
end

local function pane_context()
  local socket_path = vim.env.HERDR_SOCKET_PATH
  if socket_path == nil or socket_path == "" then
    return nil, "HERDR_SOCKET_PATH is not set"
  end

  local pane_id = vim.env.HERDR_PANE_ID
  if pane_id == nil or pane_id == "" then
    return nil, "HERDR_PANE_ID is not set"
  end

  return { socket_path = socket_path, pane_id = pane_id }, nil
end

local function close_pipe(pipe)
  if pipe and not pipe:is_closing() then
    pipe:close()
  end
end

local function decode_response(method, id, line)
  local decoded, response = pcall(vim.json.decode, line)
  if not decoded then
    return nil, "decode " .. method .. " response: " .. tostring(response)
  end
  if present(response.error) then
    return nil, "herdr " .. tostring(response.error.code) .. ": " .. tostring(response.error.message)
  end
  if response.id ~= id then
    return nil, "herdr answered " .. method .. " with request id " .. tostring(response.id)
  end
  return response.result or {}, nil
end

-- request sends one Herdr socket request and hands the result to on_done on the main loop. Herdr
-- may close a connection after one response, so every request gets its own short connection.
-- Nothing here blocks: a navigation keypress must not wait on the remote host.
local function request(socket_path, method, params, on_done)
  request_counter = request_counter + 1
  local id = "nvim-" .. request_counter
  local pipe = assert(vim.uv.new_pipe(false))
  local timer = assert(vim.uv.new_timer())
  local buffer = ""
  local settled = false

  local function finish(err, result)
    if settled then
      return
    end
    settled = true
    timer:stop()
    if not timer:is_closing() then
      timer:close()
    end
    close_pipe(pipe)
    vim.schedule(function()
      on_done(err, result)
    end)
  end

  -- A socket that accepts and then says nothing must not leave the key dead for longer than the
  -- user would wait before pressing it again, nor leave a pipe behind for the next press to
  -- stack on. Mirrors requestTimeout in cli/gty/internal/herdr/client.go.
  timer:start(request_timeout_ms, 0, function()
    finish(method .. " timed out after " .. request_timeout_ms .. "ms")
  end)

  pipe:connect(socket_path, function(connect_err)
    if connect_err then
      return finish("connect to herdr at " .. socket_path .. ": " .. tostring(connect_err))
    end

    local payload = vim.json.encode({ id = id, method = method, params = params })
    pipe:write(payload .. "\n", function(write_err)
      if write_err then
        finish("send " .. method .. ": " .. tostring(write_err))
      end
    end)

    pipe:read_start(function(read_err, chunk)
      if read_err then
        return finish("read " .. method .. " response: " .. tostring(read_err))
      end
      if not chunk then
        return finish("read " .. method .. " response: connection closed")
      end

      buffer = buffer .. chunk
      local newline = buffer:find("\n", 1, true)
      if not newline then
        return
      end

      pipe:read_stop()
      local result, decode_err = decode_response(method, id, buffer:sub(1, newline - 1))
      finish(decode_err, result)
    end)
  end)
end

local function describe_reason(reason)
  if not present(reason) or reason == "" then
    return "no reason given"
  end
  return tostring(reason)
end

-- signal_outer_layer asks Herdr's foreground client to carry the direction outward as a window
-- title. A `gty herdr attach` client removes that title from its SSH stream and focuses the
-- Ghostty split; the clear that follows restores the normal title everywhere else.
local function signal_outer_layer(context, direction)
  local params = { title = navigation_sentinel_prefix .. direction }
  request(context.socket_path, "client.window_title.set", params, function(err, result)
    if err then
      return notify(err)
    end
    if not result.changed then
      return notify(
        "herdr did not signal " .. direction .. " navigation to a client (" .. describe_reason(result.reason) .. ")"
      )
    end
    request(context.socket_path, "client.window_title.clear", vim.empty_dict(), function(clear_err)
      notify(clear_err)
    end)
  end)
end

local function focus_neighbor(context, direction)
  local params = { pane_id = context.pane_id, direction = direction }
  request(context.socket_path, "pane.focus_direction", params, function(err, result)
    if err then
      return notify(err)
    end
    local focus = result.focus or {}
    if not focus.changed then
      notify("herdr did not focus the " .. direction .. " pane (" .. describe_reason(focus.reason) .. ")")
    end
  end)
end

-- navigate takes over where Neovim ran out of windows: Herdr focuses a neighboring pane, or
-- signals the outer Ghostty layer when it has no neighbor either. A failed request is reported
-- and stops there. Navigating outward on uncertain state would skip the layer that owns the key.
function M.navigate(direction)
  local context, err = pane_context()
  if not context then
    notify(err)
    return false, err
  end

  local params = { pane_id = context.pane_id, direction = direction }
  request(context.socket_path, "pane.neighbor", params, function(neighbor_err, result)
    if neighbor_err then
      return notify(neighbor_err)
    end
    local neighbor = result.neighbor or {}
    if present(neighbor.neighbor_pane_id) then
      focus_neighbor(context, direction)
    else
      signal_outer_layer(context, direction)
    end
  end)

  return true, nil
end

-- probe reports the Herdr context navigation would use. It waits for the connection because
-- health checks may block, which navigation may not.
function M.probe()
  local context, err = pane_context()
  if not context then
    return nil, err
  end

  local pipe = assert(vim.uv.new_pipe(false))
  local state = {}
  pipe:connect(context.socket_path, function(connect_err)
    state.err = connect_err
    state.done = true
  end)
  vim.wait(1000, function()
    return state.done == true
  end, 10)
  close_pipe(pipe)

  if not state.done then
    return nil, "connect to herdr at " .. context.socket_path .. ": timed out"
  end
  if state.err then
    return nil, "connect to herdr at " .. context.socket_path .. ": " .. tostring(state.err)
  end
  return context, nil
end

return M
