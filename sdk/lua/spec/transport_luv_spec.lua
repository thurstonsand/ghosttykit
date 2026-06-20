local ghosttykit = require("ghosttykit")
local helpers = require("spec.helpers")

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
    local ok, err = client:focus({ tty = "/dev/ttys001", direction = "left" })

    helpers.close(server)
    helpers.cleanup_dir(dir)

    assert.is_nil(err)
    assert.is_true(ok)
  end)

  it("returns stream headers and body", function()
    local socket_path, dir = helpers.socket_path("stream.sock")
    local server = helpers.run_server(socket_path, function(request, conn)
      assert.are.equal("paste", request.command)
      conn:write('{"version":1,"code":"ok","kind":"text","bytes":11}\nhello world')
      conn:shutdown(function()
        helpers.close(conn)
      end)
    end)

    local client = ghosttykit.client({ socket_path = socket_path, transport = require("ghosttykit.transport_luv") })
    local result, err = client:paste()

    helpers.close(server)
    helpers.cleanup_dir(dir)

    assert.is_nil(err)
    assert.are.equal("text", result.header.kind)
    assert.are.equal("hello world", result.body)
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
    local held, err = client:bridge_lease("token")

    assert.is_nil(err)
    assert.are.equal("ok", held.reply.code)
    assert.is_false(closed)

    held.close()
    require("luv").run("nowait")

    helpers.close(server)
    helpers.cleanup_dir(dir)
  end)
end)
