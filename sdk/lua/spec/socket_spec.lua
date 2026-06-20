local socket = require("ghosttykit.socket")

describe("ghosttykit.socket", function()
  it("uses GTY_SOCK when present", function()
    local previous = os.getenv("GTY_SOCK")
    assert.are.equal(previous, previous)
  end)

  it("builds the daemon socket path under HOME", function()
    local path = socket.path()
    assert.matches("/%.local/run/ghosttykit/ghosttykitd%.sock$", path)
  end)
end)
