local lazy_spec = assert(loadfile("lazy.lua"))()

local function key_for(lhs)
  for _, key in ipairs(lazy_spec.keys) do
    if key[1] == lhs then
      return key
    end
  end
end

describe("ghosttykit.nvim lazy.nvim spec", function()
  it("loads at startup through the plugin main module", function()
    assert.are.equal("thurstonsand/ghosttykit.nvim", lazy_spec[1])
    assert.are.equal("ghosttykit.nvim", lazy_spec.main)
    assert.is_false(lazy_spec.lazy)
    assert.same({}, lazy_spec.opts)
  end)

  it("declares SDK dependency without invoking LuaRocks builds", function()
    assert.is_false(lazy_spec.build)
    assert.same({
      { "thurstonsand/ghosttykit.lua", name = "ghosttykit", build = false },
    }, lazy_spec.dependencies)
  end)

  it("declares the default navigation keys through lazy.nvim key handlers", function()
    local expected = {
      ["<C-h>"] = "left",
      ["<C-j>"] = "down",
      ["<C-k>"] = "up",
      ["<C-l>"] = "right",
    }

    assert.are.equal(4, #lazy_spec.keys)
    for lhs, direction in pairs(expected) do
      local key = assert(key_for(lhs), "missing key " .. lhs)
      assert.are.equal("GhosttyKit navigate " .. direction, key.desc)
      assert.is_function(key[2])
    end
  end)

  it("occupies LazyVim's default window navigation keyspace", function()
    assert.is_not_nil(key_for("<C-l>"))
  end)
end)
