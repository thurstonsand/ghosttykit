local M = {}

local function wait_for(done, run_once)
  while not done.finished do
    run_once()
  end
end

local function split_frame(buffer)
  local newline = buffer:find("\n", 1, true)
  if not newline then
    return nil, nil
  end
  return buffer:sub(1, newline - 1), buffer:sub(newline + 1)
end

local function close_pipe(pipe)
  if pipe and not pipe:is_closing() then
    pipe:close()
  end
end

local function connect(uv, socket_path, run_once)
  local done = { finished = false }
  local pipe = uv.new_pipe(false)
  pipe:connect(socket_path, function(err)
    done.err = err
    done.finished = true
  end)
  wait_for(done, run_once)
  if done.err then
    close_pipe(pipe)
    return nil, "connect " .. socket_path .. ": " .. tostring(done.err)
  end
  return pipe, nil
end

local function write(pipe, payload, run_once)
  local done = { finished = false }
  pipe:write(payload, function(err)
    done.err = err
    done.finished = true
  end)
  wait_for(done, run_once)
  if done.err then
    return "send request: " .. tostring(done.err)
  end
  return nil
end

local function read_frame(pipe, run_once)
  local done = { finished = false, buffer = "" }
  pipe:read_start(function(err, chunk)
    if err then
      done.err = err
      done.finished = true
      return
    end
    if chunk then
      done.buffer = done.buffer .. chunk
      local frame, rest = split_frame(done.buffer)
      if frame then
        pipe:read_stop()
        done.frame = frame
        done.rest = rest
        done.finished = true
      end
      return
    end
    done.eof = true
    done.finished = true
  end)
  wait_for(done, run_once)
  if done.err then
    return nil, nil, "read reply: " .. tostring(done.err)
  end
  if not done.frame then
    return nil, nil, "read reply: EOF"
  end
  return done.frame, done.rest or "", nil
end

local function read_to_eof(pipe, initial, run_once)
  local done = { finished = false, chunks = { initial or "" } }
  pipe:read_start(function(err, chunk)
    if err then
      done.err = err
      done.finished = true
      return
    end
    if chunk then
      table.insert(done.chunks, chunk)
      return
    end
    done.finished = true
  end)
  wait_for(done, run_once)
  if done.err then
    return nil, tostring(done.err)
  end
  return table.concat(done.chunks), nil
end

local function stream_reader(pipe, initial, run_once)
  local reader = {
    pipe = pipe,
    pending = initial or "",
    closed = false,
    eof = false,
  }

  function reader:read()
    if self.closed then
      return nil, "stream is closed"
    end
    if self.pending ~= "" then
      local chunk = self.pending
      self.pending = ""
      return chunk, nil
    end
    if self.eof then
      return nil, nil
    end

    local done = { finished = false }
    self.pipe:read_start(function(err, chunk)
      self.pipe:read_stop()
      if err then
        done.err = err
        done.finished = true
        return
      end
      if chunk then
        done.chunk = chunk
        done.finished = true
        return
      end
      self.eof = true
      done.finished = true
    end)
    wait_for(done, run_once)
    if done.err then
      return nil, tostring(done.err)
    end
    return done.chunk, nil
  end

  function reader:read_all()
    local chunks = {}
    while true do
      local chunk, err = self:read()
      if err then
        return nil, err
      end
      if not chunk then
        return table.concat(chunks), nil
      end
      table.insert(chunks, chunk)
    end
  end

  function reader:close()
    self.closed = true
    close_pipe(self.pipe)
  end

  return reader
end

function M.new(uv, json, run_once)
  return {
    request = function(_, socket_path, payload, mode)
      local pipe, err = connect(uv, socket_path, run_once)
      if err then
        return nil, err
      end

      err = write(pipe, payload, run_once)
      if err then
        close_pipe(pipe)
        return nil, err
      end

      if mode == "none" then
        local body
        body, err = read_to_eof(pipe, "", run_once)
        close_pipe(pipe)
        if err then
          return nil, "wait for daemon completion: " .. err
        end
        if body ~= "" then
          return nil, "daemon sent unexpected data for no-reply request"
        end
        return {}, nil
      end

      local frame, rest
      frame, rest, err = read_frame(pipe, run_once)
      if err then
        close_pipe(pipe)
        return nil, err
      end

      local reply = json.decode(frame)
      if mode == "stream" then
        return { header = reply, body = stream_reader(pipe, rest, run_once) }, nil
      end

      if mode == "hold" then
        return {
          reply = reply,
          close = function()
            close_pipe(pipe)
          end,
        },
          nil
      end

      close_pipe(pipe)
      return reply, nil
    end,
  }
end

return M
