local M = {}

local uv = require("luv")
local json = require("dkjson")

function M.socket_path(name)
  local dir = os.tmpname()
  os.remove(dir)
  assert(uv.fs_mkdir(dir, 448))
  return dir .. "/" .. (name or "ghosttykit.sock"), dir
end

function M.cleanup_dir(dir)
  local handle = uv.fs_scandir(dir)
  if handle then
    while true do
      local name = uv.fs_scandir_next(handle)
      if not name then
        break
      end
      os.remove(dir .. "/" .. name)
    end
  end
  uv.fs_rmdir(dir)
end

function M.run_server(socket_path, handler)
  local server = uv.new_pipe(false)
  assert(server:bind(socket_path))
  assert(server:listen(1, function(err)
    assert(err == nil, tostring(err))
    local conn = uv.new_pipe(false)
    server:accept(conn)
    local buffer = ""
    conn:read_start(function(read_err, chunk)
      assert(read_err == nil, tostring(read_err))
      if not chunk then
        return
      end
      buffer = buffer .. chunk
      local newline = buffer:find("\n", 1, true)
      if not newline then
        return
      end
      conn:read_stop()
      local request = json.decode(buffer:sub(1, newline - 1))
      handler(request, conn)
    end)
  end))
  return server
end

function M.close(handle)
  if handle and not handle:is_closing() then
    handle:close()
  end
end

return M
