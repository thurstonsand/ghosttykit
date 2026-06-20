local ghosttykit = require("ghosttykit")

describe("ghosttykit nvim transport", function()
  it("calls doctor over a Unix socket", function()
    assert.is_table(vim)
    assert.is_table(vim.uv)

    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    local socket_path = dir .. "/doctor.sock"
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
        assert.are.equal("doctor", request.command)
        conn:write('{"version":1,"code":"ok","healthy":true}\n')
        conn:shutdown(function()
          conn:close()
        end)
      end)
    end))

    local client = ghosttykit.client({ socket_path = socket_path, transport = require("ghosttykit.transport_nvim") })
    local reply, call_err = client:doctor()

    server:close()
    vim.fn.delete(dir, "rf")

    assert.is_nil(call_err)
    if not reply then
      error("expected doctor reply")
    end

    assert.is_true(reply.healthy)
  end)
end)
