local config = require("ghosttykit.nvim.config")
local navigation = require("ghosttykit.nvim.navigation")

describe("ghosttykit.nvim.navigation", function()
  before_each(function()
    config.setup({ notify_errors = false })
    vim.cmd("silent! only")
  end)

  it("moves to an adjacent Neovim window", function()
    vim.cmd("vsplit")
    local left = vim.fn.win_getid(1)
    vim.api.nvim_set_current_win(vim.fn.win_getid(2))

    navigation.navigate("left")

    assert.are.equal(left, vim.api.nvim_get_current_win())
  end)
end)
