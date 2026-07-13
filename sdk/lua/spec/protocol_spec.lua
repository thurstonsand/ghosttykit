local protocol = require("ghosttykit.protocol")
local json = require("dkjson")

describe("ghosttykit.protocol", function()
  it("encodes request envelopes without internal reply metadata", function()
    local request = protocol.focus({ tty = "/dev/ttys001", direction = "left", ack = true })
    local encoded = protocol.encode_request(request, json)
    local decoded = json.decode(encoded)

    assert.are.equal(1, decoded.version)
    assert.are.equal("focus", decoded.command)
    assert.are.equal("/dev/ttys001", decoded.tty)
    assert.are.equal("left", decoded.direction)
    assert.is_true(decoded.ack)
    assert.is_nil(decoded._reply_mode)
  end)

  it("requires resolved ttys", function()
    assert.has_error(function()
      protocol.terminal_id()
    end, "tty is required")
  end)

  it("reports reply modes", function()
    assert.are.equal(protocol.reply_mode.frame, protocol.reply_mode_of(protocol.doctor()))
    local tty = "/dev/ttys001"
    assert.are.equal(
      protocol.reply_mode.none,
      protocol.reply_mode_of(protocol.focus({ tty = tty, direction = "left" }))
    )
    assert.are.equal(
      protocol.reply_mode.frame,
      protocol.reply_mode_of(protocol.focus({ tty = tty, direction = "left", ack = true }))
    )
    assert.are.equal(protocol.reply_mode.none, protocol.reply_mode_of(protocol.input({ tty = tty, text = "echo hi" })))
    assert.are.equal(
      protocol.reply_mode.frame,
      protocol.reply_mode_of(protocol.input({ tty = tty, text = "echo hi", ack = true }))
    )
    assert.are.equal(protocol.reply_mode.stream, protocol.reply_mode_of(protocol.paste()))
    assert.are.equal(protocol.reply_mode.hold, protocol.reply_mode_of(protocol.bridge_lease("token")))
  end)

  it("encodes input requests with optional booleans omitted unless true", function()
    local request = protocol.input({ tty = "/dev/ttys001", text = "echo hi", submit = false, ack = false })
    local decoded = json.decode(protocol.encode_request(request, json))

    assert.are.equal(1, decoded.version)
    assert.are.equal("input", decoded.command)
    assert.are.equal("/dev/ttys001", decoded.tty)
    assert.are.equal("echo hi", decoded.text)
    assert.is_nil(decoded.submit)
    assert.is_nil(decoded.ack)

    decoded = json.decode(
      protocol.encode_request(
        protocol.input({ tty = "/dev/ttys001", text = "echo hi", submit = true, ack = true }),
        json
      )
    )

    assert.is_true(decoded.submit)
    assert.is_true(decoded.ack)
  end)
end)
