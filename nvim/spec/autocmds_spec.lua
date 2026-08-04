local function reset_ghosttykit_modules()
  for name in pairs(package.loaded) do
    if name == "ghosttykit.nvim" or name:match("^ghosttykit%.nvim%.") then
      package.loaded[name] = nil
    end
  end
end

local function autocmd_count(event)
  return #vim.api.nvim_get_autocmds({ group = "ghosttykit", event = event })
end

describe("ghosttykit.nvim autocmds", function()
  local term_program
  local herdr_env

  before_each(function()
    term_program = vim.env.TERM_PROGRAM
    herdr_env = vim.env.HERDR_ENV
    vim.env.TERM_PROGRAM = "ghostty"
    vim.env.HERDR_ENV = nil
    pcall(vim.api.nvim_del_augroup_by_name, "ghosttykit")
    reset_ghosttykit_modules()
  end)

  after_each(function()
    vim.env.TERM_PROGRAM = term_program
    vim.env.HERDR_ENV = herdr_env
    pcall(vim.api.nvim_del_augroup_by_name, "ghosttykit")
    reset_ghosttykit_modules()
  end)

  it("keeps persistent autocmds when client calls succeed", function()
    local calls = { activate = 0, deactivate = 0 }
    package.loaded["ghosttykit.nvim.client"] = {
      activate_key_table = function()
        calls.activate = calls.activate + 1
        return true, nil
      end,
      deactivate_key_table = function()
        calls.deactivate = calls.deactivate + 1
        return true, nil
      end,
    }

    require("ghosttykit.nvim").setup({})

    assert.are.equal(1, autocmd_count("FocusGained"))
    assert.are.equal(1, autocmd_count("VimSuspend"))
    assert.same({ activate = 1, deactivate = 0 }, calls)

    vim.api.nvim_exec_autocmds("FocusGained", { group = "ghosttykit" })
    vim.api.nvim_exec_autocmds("VimSuspend", { group = "ghosttykit" })

    assert.same({ activate = 2, deactivate = 1 }, calls)
    assert.are.equal(1, autocmd_count("FocusGained"))
    assert.are.equal(1, autocmd_count("VimSuspend"))
  end)

  it("leaves the key table to gty herdr attach inside Herdr", function()
    local calls = { activate = 0, deactivate = 0 }
    package.loaded["ghosttykit.nvim.client"] = {
      activate_key_table = function()
        calls.activate = calls.activate + 1
        return true, nil
      end,
      deactivate_key_table = function()
        calls.deactivate = calls.deactivate + 1
        return true, nil
      end,
    }
    vim.env.HERDR_ENV = "1"

    require("ghosttykit.nvim").setup({})

    assert.same({ activate = 0, deactivate = 0 }, calls)
    assert.has_error(function()
      vim.api.nvim_get_autocmds({ group = "ghosttykit" })
    end)
    assert.are_not.equal("", vim.fn.maparg("<Plug>(GhosttyKitNavigateLeft)", "n"))
  end)
end)
