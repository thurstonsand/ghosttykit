local errors = require("ghosttykit.error")

describe("ghosttykit.error", function()
  it("maps known response codes to stable names", function()
    local err = errors.from_reply({ code = "terminal_not_found", error = "missing" })

    if not err then
      error("expected error response")
    end

    assert.are.equal("terminal_not_found", err.code)
    assert.are.equal("TerminalNotFoundError", err.name)
    assert.are.equal("terminal_not_found: missing", tostring(err))
  end)

  it("returns nil for ok replies", function()
    assert.is_nil(errors.from_reply({ code = "ok" }))
  end)
end)
