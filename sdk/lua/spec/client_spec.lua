local ghosttykit = require("ghosttykit")
local tty = require("ghosttykit.tty")

local original_resolve_tty = tty.resolve

local function transport(replies)
  local calls = {}
  return {
    calls = calls,
    request = function(_, socket_path, payload, mode)
      table.insert(calls, { socket_path = socket_path, payload = payload, mode = mode })
      local reply = table.remove(replies, 1)
      if type(reply) == "function" then
        return reply(calls[#calls])
      end
      return reply, nil
    end,
  }
end

local function stream_body(chunks)
  return {
    closed = false,
    read = function(self)
      return table.remove(chunks, 1), nil
    end,
    close = function(self)
      self.closed = true
    end,
  }
end

describe("ghosttykit client", function()
  before_each(function()
    rawset(tty, "resolve", function(value)
      return value or "/dev/ttys001"
    end)
  end)

  after_each(function()
    rawset(tty, "resolve", original_resolve_tty)
  end)

  it("returns high-level doctor status", function()
    local tx = transport({ { version = 1, code = "ok", healthy = true } })
    local client = ghosttykit.client({ socket_path = "/tmp/gty.sock", transport = tx })

    local status, err = client:doctor()

    assert.is_nil(err)
    if not status then
      error("expected doctor status")
    end
    assert.is_true(status.healthy)
    assert.same({}, status.checks)
  end)

  it("returns terminal values instead of protocol frames", function()
    local tx = transport({
      { version = 1, code = "ok", value = "terminal-1" },
      { version = 1, code = "ok", value = "3" },
    })
    local client = ghosttykit.client({ socket_path = "/tmp/gty.sock", transport = tx })

    local id, id_err = client.terminal:id()
    local count, count_err = client.terminal:count()

    assert.is_nil(id_err)
    assert.is_nil(count_err)
    assert.are.equal("terminal-1", id)
    assert.are.equal(3, count)
    assert.is_true(tx.calls[1].payload:match('"tty":"/dev/ttys001"') ~= nil)
    assert.is_true(tx.calls[2].payload:match('"tty":"/dev/ttys001"') ~= nil)
  end)

  it("reports tty resolution failures before transport", function()
    rawset(tty, "resolve", function()
      return nil
    end)
    local tx = transport({})
    local client = ghosttykit.client({ socket_path = "/tmp/gty.sock", transport = tx })

    local value, err = client.terminal:id()

    assert.is_nil(value)
    assert.are.equal("invalid_request", err.code)
    assert.are.equal(0, #tx.calls)
  end)

  it("uses domain command tables", function()
    local tx = transport({ {}, { version = 1, code = "ok" }, {}, {}, {} })
    local client = ghosttykit.client({ socket_path = "/tmp/gty.sock", transport = tx })

    assert.is_true((client.key_table:activate({ name = "nvim", tty = "/dev/ttys001" })))
    assert.is_true((client.layout:focus({ direction = "left", tty = "/dev/ttys001", ack = true })))
    assert.is_true((client.layout:split({ direction = "right", cwd = "/tmp" })))
    assert.is_true((client.layout:resize({ direction = "up", pixels = 20 })))
    assert.is_true((client.layout:resize({ direction = "down", percent = 10 })))

    assert.is_true(tx.calls[1].payload:match('"table":"nvim"') ~= nil)
    assert.is_true(tx.calls[1].payload:match('"name"') == nil)
    assert.are.equal("none", tx.calls[1].mode)
    assert.are.equal("frame", tx.calls[2].mode)
    assert.is_true(tx.calls[3].payload:match('"commandText"') == nil)
    assert.is_true(tx.calls[4].payload:match('"pixels":20') ~= nil)
    assert.is_true(tx.calls[5].payload:match('"percent":10') ~= nil)
  end)

  it("returns waited split tty values without requiring them", function()
    local tx = transport({
      { version = 1, code = "ok", value = "/dev/ttys024" },
      { version = 1, code = "ok" },
    })
    local client = ghosttykit.client({ socket_path = "/tmp/gty.sock", transport = tx })

    local split_tty, tty_err = client.layout:split({ direction = "right", tty = "/dev/ttys001", ack = true })
    local empty, empty_err = client.layout:split({ direction = "right", tty = "/dev/ttys001", ack = true })

    assert.is_nil(tty_err)
    assert.is_nil(empty_err)
    assert.are.equal("/dev/ttys024", split_tty)
    assert.is_nil(empty)
  end)

  it("sends input as an ack-style terminal command", function()
    local tx = transport({ { version = 1, code = "ok" } })
    local client = ghosttykit.client({ socket_path = "/tmp/gty.sock", transport = tx })

    local ok, err = client.terminal:input({ tty = "/dev/ttys001", text = "echo hi", submit = true, ack = true })

    assert.is_nil(err)
    assert.is_true(ok)
    assert.are.equal("frame", tx.calls[1].mode)
    assert.is_true(tx.calls[1].payload:match('"command":"input"') ~= nil)
    assert.is_true(tx.calls[1].payload:match('"text":"echo hi"') ~= nil)
    assert.is_true(tx.calls[1].payload:match('"submit":true') ~= nil)
  end)

  it("keeps raw protocol calls available", function()
    local tx = transport({ { version = 1, code = "ok", value = "raw" } })
    local client = ghosttykit.client({ socket_path = "/tmp/gty.sock", transport = tx })

    local reply, err = client.raw:call(ghosttykit.protocol.terminal_id({ tty = "/dev/ttys001" }))

    assert.is_nil(err)
    assert.are.equal("raw", reply.value)
  end)

  it("reads text paste into memory", function()
    local body = stream_body({ "hello", " world" })
    local tx = transport({
      {
        header = { version = 1, code = "ok", kind = "text", bytes = 11 },
        body = body,
      },
    })
    local client = ghosttykit.client({ socket_path = "/tmp/gty.sock", transport = tx })

    local paste = assert(client.paste:get())
    local text = assert(paste:text())

    assert.are.equal("hello world", text)
    assert.are.equal("consumed", paste.state)
    assert.is_true(body.closed)
  end)

  it("streams pasted file payloads to disk", function()
    local body = stream_body({ "hel", "lowor", "ld" })
    local tx = transport({
      {
        header = {
          version = 1,
          code = "ok",
          kind = "files",
          bytes = 10,
          files = {
            { fileName = "one.txt", mediaType = "text/plain", bytes = 5 },
            { fileName = "nested/two.txt", mediaType = "text/plain", bytes = 5 },
          },
        },
        body = body,
      },
    })
    local client = ghosttykit.client({ socket_path = "/tmp/gty.sock", transport = tx })
    local dir = os.tmpname()
    os.remove(dir)

    local paste = assert(client.paste:get())
    local saved = assert(paste:save({ dir = dir }))

    local first = assert(io.open(saved[1].path, "rb"))
    local second = assert(io.open(saved[2].path, "rb"))
    assert.are.equal("hello", first:read("*a"))
    assert.are.equal("world", second:read("*a"))
    assert.is_true(saved[1].path:match("one%-[%da-f]+%.txt$") ~= nil)
    assert.is_true(saved[2].path:match("two%-[%da-f]+%.txt$") ~= nil)
    first:close()
    second:close()
    os.remove(saved[1].path)
    os.remove(saved[2].path)
    os.remove(dir)
  end)

  it("creates bridge handles with leases", function()
    local closed = false
    local tx = transport({
      { version = 1, code = "ok", socketPath = "/tmp/bridge.sock", leaseToken = "lease-token" },
      {
        reply = { version = 1, code = "ok" },
        close = function()
          closed = true
        end,
      },
    })
    local client = ghosttykit.client({ socket_path = "/tmp/gty.sock", transport = tx })

    local bridge, err = client.bridge:create({ tty = "/dev/ttys001" })

    assert.is_nil(err)
    if not bridge then
      error("expected bridge")
    end
    assert.are.equal("/tmp/bridge.sock", bridge.socket_path)
    assert.are.equal("/tmp/bridge.sock", tx.calls[2].socket_path)

    bridge:close()
    assert.is_true(closed)
  end)
end)
