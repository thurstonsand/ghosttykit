local config = require("ghosttykit.nvim.config")

describe("ghosttykit.nvim.config", function()
  it("uses GhosttyKit defaults", function()
    local result = config.setup()

    assert.are.equal("nvim", result.key_table)
    assert.is_true(result.focused)
    assert.are.equal("previous", result.float_win_behavior)
    assert.is_false(result.notify_errors)
  end)

  it("merges user options with defaults", function()
    local result = config.setup({ focused = false, float_win_behavior = "mux" })

    assert.is_false(result.focused)
    assert.are.equal("mux", result.float_win_behavior)
    assert.are.equal("nvim", result.key_table)
  end)

  it("rejects invalid float behavior", function()
    assert.has_error(function()
      config.setup({ float_win_behavior = "invalid" })
    end)
  end)
end)
