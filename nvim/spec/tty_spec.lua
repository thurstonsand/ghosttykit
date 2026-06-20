local tty = require("ghosttykit.nvim.tty")

describe("ghosttykit.nvim.tty", function()
  it("returns nil when no nvim-tui is attached in headless mode", function()
    tty.reset()
    assert.is_nil(tty.current())
  end)
end)
