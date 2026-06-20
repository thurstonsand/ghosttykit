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

  it("reports reply modes", function()
    assert.are.equal(protocol.reply_mode.frame, protocol.reply_mode_of(protocol.doctor()))
    assert.are.equal(protocol.reply_mode.none, protocol.reply_mode_of(protocol.focus({ direction = "left" })))
    assert.are.equal(
      protocol.reply_mode.frame,
      protocol.reply_mode_of(protocol.focus({ direction = "left", ack = true }))
    )
    assert.are.equal(protocol.reply_mode.stream, protocol.reply_mode_of(protocol.paste()))
    assert.are.equal(protocol.reply_mode.hold, protocol.reply_mode_of(protocol.bridge_lease("token")))
  end)
end)
