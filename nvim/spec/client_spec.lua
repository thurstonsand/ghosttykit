local function reset_ghosttykit_modules()
  for name in pairs(package.loaded) do
    if name == "ghosttykit" or name == "ghosttykit.nvim.client" then
      package.loaded[name] = nil
    end
  end
end

describe("ghosttykit.nvim.client", function()
  before_each(function()
    reset_ghosttykit_modules()
    package.loaded["ghosttykit.nvim.config"] = {
      get = function()
        return {
          focused = true,
          key_table = "nvim",
          notify_errors = false,
        }
      end,
    }
    package.loaded["ghosttykit.nvim.tty"] = {
      current = function()
        return "/dev/ttys001"
      end,
    }
  end)

  after_each(function()
    package.loaded["ghosttykit.nvim.config"] = nil
    package.loaded["ghosttykit.nvim.tty"] = nil
    reset_ghosttykit_modules()
  end)

  it("uses the Lua SDK domain API", function()
    local calls = {}
    package.loaded["ghosttykit"] = {
      client = function()
        return {
          key_table = {
            activate = function(_, opts)
              table.insert(calls, { "key_table.activate", opts })
              return true, nil
            end,
          },
          layout = {
            focus = function(_, opts)
              table.insert(calls, { "layout.focus", opts })
              return true, nil
            end,
          },
        }
      end,
    }

    local client = require("ghosttykit.nvim.client")
    client.activate_key_table()
    client.focus("left")

    assert.are.equal("key_table.activate", calls[1][1])
    assert.same({ tty = "/dev/ttys001", focused = true, name = "nvim", ack = false }, calls[1][2])
    assert.are.equal("layout.focus", calls[2][1])
    assert.same({ tty = "/dev/ttys001", focused = true, direction = "left", ack = false }, calls[2][2])
  end)
end)
