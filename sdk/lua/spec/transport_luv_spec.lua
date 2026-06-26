local ghosttykit = require("ghosttykit")
local helpers = require("spec.helpers")
local uv = require("luv")

describe("ghosttykit luv transport", function()
  it("calls doctor over a Unix socket", function()
    local socket_path, dir = helpers.socket_path("doctor.sock")
    local server = helpers.run_server(socket_path, function(request, conn)
      assert.are.equal("doctor", request.command)
      conn:write('{"version":1,"code":"ok","healthy":true,"checks":[{"name":"daemon","status":"ok"}]}\n')
      conn:shutdown(function()
        helpers.close(conn)
      end)
    end)

    local client = ghosttykit.client({ socket_path = socket_path, transport = require("ghosttykit.transport_luv") })
    local reply, err = client:doctor()

    helpers.close(server)
    helpers.cleanup_dir(dir)

    assert.is_nil(err)
    if not reply then
      error("expected doctor reply")
    end
    assert.is_true(reply.healthy)
    assert.are.equal("daemon", reply.checks[1].name)
  end)

  it("waits for EOF for no-reply requests", function()
    local socket_path, dir = helpers.socket_path("notify.sock")
    local server = helpers.run_server(socket_path, function(request, conn)
      assert.are.equal("focus", request.command)
      conn:shutdown(function()
        helpers.close(conn)
      end)
    end)

    local client = ghosttykit.client({ socket_path = socket_path, transport = require("ghosttykit.transport_luv") })
    local ok, err = client.layout:focus({ tty = "/dev/ttys001", direction = "left" })

    helpers.close(server)
    helpers.cleanup_dir(dir)

    assert.is_nil(err)
    assert.is_true(ok)
  end)

  it("returns a lazy stream body", function()
    local socket_path, dir = helpers.socket_path("stream.sock")
    local stream_conn
    local sent_rest = false
    local timer
    local server = helpers.run_server(socket_path, function(request, conn)
      assert.are.equal("paste", request.command)
      stream_conn = conn
      conn:write('{"version":1,"code":"ok","kind":"text","bytes":11}\nhello')
      timer = assert(uv.new_timer())
      timer:start(100, 0, function()
        sent_rest = true
        timer:close()
        stream_conn:write(" world")
        stream_conn:shutdown(function()
          helpers.close(stream_conn)
        end)
      end)
    end)

    local client = ghosttykit.client({ socket_path = socket_path, transport = require("ghosttykit.transport_luv") })
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
    helpers.close(server)
    helpers.cleanup_dir(dir)

    assert.is_nil(rest_err)
    assert.are.equal(" world", rest)
  end)

  it("keeps hold connections open until closed", function()
    local socket_path, dir = helpers.socket_path("hold.sock")
    local closed = false
    local server = helpers.run_server(socket_path, function(request, conn)
      assert.are.equal("bridge-lease", request.command)
      conn:write('{"version":1,"code":"ok"}\n')
      conn:read_start(function(_, chunk)
        if not chunk then
          closed = true
          helpers.close(conn)
        end
      end)
    end)

    local client = ghosttykit.client({ socket_path = socket_path, transport = require("ghosttykit.transport_luv") })
    local held, err = client.raw:hold(ghosttykit.protocol.bridge_lease("token"))

    assert.is_nil(err)
    assert.are.equal("ok", held.reply.code)
    assert.is_false(closed)

    held.close()
    require("luv").run("nowait")

    helpers.close(server)
    helpers.cleanup_dir(dir)
  end)
end)
