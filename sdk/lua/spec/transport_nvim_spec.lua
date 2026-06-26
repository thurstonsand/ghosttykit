local ghosttykit = require("ghosttykit")

local function close(handle)
  if handle and not handle:is_closing() then
    handle:close()
  end
end

local function run_server(socket_path, handler)
  local server = assert(vim.uv.new_pipe(false))
  assert(server:bind(socket_path))
  assert(server:listen(1, function(err)
    assert.is_nil(err)
    local conn = assert(vim.uv.new_pipe(false))
    server:accept(conn)
    local buffer = ""
    conn:read_start(function(read_err, chunk)
      assert.is_nil(read_err)
      if not chunk then
        return
      end
      buffer = buffer .. chunk
      local newline = buffer:find("\n", 1, true)
      if not newline then
        return
      end
      conn:read_stop()
      local request = vim.json.decode(buffer:sub(1, newline - 1))
      handler(request, conn)
    end)
  end))
  return server
end

describe("ghosttykit nvim transport", function()
  it("calls doctor over a Unix socket", function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    local socket_path = dir .. "/doctor.sock"
    local server = run_server(socket_path, function(request, conn)
      assert.are.equal("doctor", request.command)
      conn:write('{"version":1,"code":"ok","healthy":true}\n')
      conn:shutdown(function()
        close(conn)
      end)
    end)

    local client = ghosttykit.client({ socket_path = socket_path, transport = require("ghosttykit.transport_nvim") })
    local reply, call_err = client:doctor()

    close(server)
    vim.fn.delete(dir, "rf")

    assert.is_nil(call_err)
    if not reply then
      error("expected doctor reply")
    end

    assert.is_true(reply.healthy)
  end)

  it("returns a lazy stream body", function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    local socket_path = dir .. "/stream.sock"
    local stream_conn
    local sent_rest = false
    local timer
    local server = run_server(socket_path, function(request, conn)
      assert.are.equal("paste", request.command)
      stream_conn = conn
      conn:write('{"version":1,"code":"ok","kind":"text","bytes":11}\nhello')
      timer = assert(vim.uv.new_timer())
      timer:start(100, 0, function()
        sent_rest = true
        timer:close()
        stream_conn:write(" world")
        stream_conn:shutdown(function()
          close(stream_conn)
        end)
      end)
    end)

    local client = ghosttykit.client({ socket_path = socket_path, transport = require("ghosttykit.transport_nvim") })
    local result, err = client.raw:stream(ghosttykit.protocol.paste())

    assert.is_nil(err)
    if not result then
      error("expected paste result")
    end
    assert.are.equal("text", result.header.kind)
    assert.are.equal(11, result.header.bytes)
    assert.is_false(sent_rest)

    local first, first_err = result.body:read()
    assert.is_nil(first_err)
    assert.are.equal("hello", first)

    local rest, rest_err = result.body:read_all()
    result.body:close()
    close(server)
    vim.fn.delete(dir, "rf")

    assert.is_nil(rest_err)
    assert.are.equal(" world", rest)
  end)
end)
