local keymaps = require("ghosttykit.nvim.keymaps")

local function reset_navigation_maps()
  for _, key in ipairs({ "<C-h>", "<C-j>", "<C-k>", "<C-l>" }) do
    vim.cmd("silent! nunmap " .. key)
  end
end

local function reset_ghosttykit_modules()
  for name in pairs(package.loaded) do
    if name == "ghosttykit.nvim" or name:match("^ghosttykit%.nvim%.") then
      package.loaded[name] = nil
    end
  end
end

describe("ghosttykit.nvim.keymaps", function()
  before_each(function()
    reset_navigation_maps()
  end)

  it("defines plug mappings", function()
    keymaps.setup_plug_mappings()

    assert.is_not_nil(vim.fn.maparg("<Plug>(GhosttyKitNavigateLeft)", "n", false, true).callback)
    assert.is_not_nil(vim.fn.maparg("<Plug>(GhosttyKitNavigateRight)", "n", false, true).callback)
  end)

  it("does not define direct navigation mappings during setup", function()
    require("ghosttykit.nvim").setup({})

    assert.are.equal("", vim.fn.maparg("<C-l>", "n"))
  end)

  it("supports non-lazy setup with user-defined plug mappings", function()
    reset_ghosttykit_modules()
    require("ghosttykit.nvim").setup({})

    local original = package.loaded["ghosttykit.nvim"]
    local calls = {}
    package.loaded["ghosttykit.nvim"] = {
      navigate = function(direction)
        table.insert(calls, direction)
        return true, nil
      end,
    }

    vim.keymap.set("n", "<C-l>", "<Plug>(GhosttyKitNavigateRight)")

    local lhs = vim.api.nvim_replace_termcodes("<C-l>", true, false, true)
    vim.api.nvim_feedkeys(lhs, "x", false)

    vim.keymap.del("n", "<C-l>")
    package.loaded["ghosttykit.nvim"] = original

    assert.same({ "right" }, calls)
  end)

  it("invokes navigation through custom plug mappings", function()
    local original = package.loaded["ghosttykit.nvim"]
    local calls = {}
    package.loaded["ghosttykit.nvim"] = {
      navigate = function(direction)
        table.insert(calls, direction)
        return true, nil
      end,
    }

    keymaps.setup_plug_mappings()
    vim.keymap.set("n", "<leader>h", "<Plug>(GhosttyKitNavigateLeft)")

    local lhs = vim.api.nvim_replace_termcodes("<leader>h", true, false, true)
    vim.api.nvim_feedkeys(lhs, "x", false)

    vim.keymap.del("n", "<leader>h")
    package.loaded["ghosttykit.nvim"] = original

    assert.same({ "left" }, calls)
  end)
end)
