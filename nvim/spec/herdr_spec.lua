local config = require("ghosttykit.nvim.config")
local env = require("ghosttykit.nvim.env")
local herdr = require("ghosttykit.nvim.herdr")

local function with_env(values, run)
  local saved = {}
  for name, value in pairs(values) do
    saved[name] = vim.env[name]
    vim.env[name] = value ~= vim.NIL and value or nil
  end
  local ok, err = pcall(run)
  for name, _ in pairs(values) do
    vim.env[name] = saved[name]
  end
  if not ok then
    error(err)
  end
end

-- fake_herdr serves Herdr's newline-delimited JSON protocol from a real unix socket, answering
-- each request from a canned table keyed by method and recording what it was asked.
-- silent marks a method the fake server accepts and records but never answers.
local silent = {}

local function fake_herdr(replies)
  local server = {
    socket_path = vim.fn.tempname(),
    requests = {},
    clients = {},
  }
  server.handle = assert(vim.uv.new_pipe(false))
  assert(server.handle:bind(server.socket_path))

  assert(server.handle:listen(16, function()
    local client = assert(vim.uv.new_pipe(false))
    table.insert(server.clients, client)
    server.handle:accept(client)
    client:read_start(function(err, chunk)
      if err or not chunk then
        return
      end
      local request = vim.json.decode(vim.trim(chunk))
      table.insert(server.requests, request)
      local reply = replies[request.method]
      if reply == silent then
        return
      end
      if reply == nil then
        reply = { error = { code = "not_found", message = "unexpected method " .. request.method } }
      end
      reply = vim.deepcopy(reply)
      reply.id = reply.id or request.id
      client:write(vim.json.encode(reply) .. "\n")
    end)
  end))

  function server:methods()
    local names = {}
    for _, request in ipairs(self.requests) do
      table.insert(names, request.method)
    end
    return names
  end

  function server:wait(count)
    vim.wait(2000, function()
      return #self.requests >= count
    end, 5)
    -- Let the final response settle so a trailing request cannot arrive after the assertion.
    vim.wait(50)
    return self:methods()
  end

  function server:close()
    for _, client in ipairs(self.clients) do
      if not client:is_closing() then
        client:close()
      end
    end
    if not self.handle:is_closing() then
      self.handle:close()
    end
  end

  return server
end

local function with_herdr(replies, run)
  local server = fake_herdr(replies)
  local warnings = {}
  local notify = vim.notify
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.notify = function(message)
    table.insert(warnings, message)
  end

  local ok, err = pcall(function()
    with_env({ HERDR_SOCKET_PATH = server.socket_path, HERDR_PANE_ID = "w1:p1" }, function()
      run(server, warnings)
    end)
  end)

  vim.notify = notify
  server:close()
  if not ok then
    error(err)
  end
end

local neighbor_present = {
  ["pane.neighbor"] = {
    result = { type = "pane_neighbor", neighbor = { pane_id = "w1:p1", neighbor_pane_id = "w1:p2" } },
  },
}

local neighbor_absent = {
  ["pane.neighbor"] = { result = { type = "pane_neighbor", neighbor = { pane_id = "w1:p1" } } },
}

describe("ghosttykit.nvim.env", function()
  it("detects a Herdr pane", function()
    with_env({ HERDR_ENV = "1" }, function()
      assert.is_true(env.in_herdr())
    end)
    with_env({ HERDR_ENV = "0" }, function()
      assert.is_false(env.in_herdr())
    end)
    with_env({ HERDR_ENV = vim.NIL }, function()
      assert.is_false(env.in_herdr())
    end)
  end)
end)

describe("ghosttykit.nvim.herdr", function()
  before_each(function()
    config.setup({ notify_errors = true })
  end)

  after_each(function()
    config.setup({})
  end)

  it("focuses the Herdr neighbor when one exists", function()
    local replies = vim.tbl_extend("force", neighbor_present, {
      ["pane.focus_direction"] = {
        result = { type = "pane_focus_direction", focus = { changed = true, focused_pane_id = "w1:p2" } },
      },
    })
    with_herdr(replies, function(server, warnings)
      assert.is_true(herdr.navigate("left"))
      assert.same({ "pane.neighbor", "pane.focus_direction" }, server:wait(2))
      assert.same({ pane_id = "w1:p1", direction = "left" }, server.requests[2].params)
      assert.same({}, warnings)
    end)
  end)

  it("sets then clears the sentinel title at the Herdr edge", function()
    local replies = vim.tbl_extend("force", neighbor_absent, {
      ["client.window_title.set"] = { result = { type = "client_window_title", changed = true, reason = "set" } },
      ["client.window_title.clear"] = { result = { type = "client_window_title", changed = true, reason = "cleared" } },
    })
    with_herdr(replies, function(server, warnings)
      assert.is_true(herdr.navigate("up"))
      assert.same({ "pane.neighbor", "client.window_title.set", "client.window_title.clear" }, server:wait(3))
      assert.are.equal("gty-nav:v1:up", server.requests[2].params.title)
      assert.same({}, warnings)
    end)
  end)

  it("reports an API error and never falls through", function()
    local replies = {
      ["pane.neighbor"] = { error = { code = "not_found", message = "pane not found" } },
    }
    with_herdr(replies, function(server, warnings)
      assert.is_true(herdr.navigate("right"))
      assert.same({ "pane.neighbor" }, server:wait(1))
      assert.are.equal(1, #warnings)
      assert.is_truthy(tostring(warnings[1]):find("not_found", 1, true))
    end)
  end)

  it("treats an unchanged focus as a failure", function()
    local replies = vim.tbl_extend("force", neighbor_present, {
      ["pane.focus_direction"] = {
        result = { type = "pane_focus_direction", focus = { changed = false, reason = "no_neighbor" } },
      },
    })
    with_herdr(replies, function(server, warnings)
      herdr.navigate("down")
      server:wait(2)
      assert.are.equal(1, #warnings)
      assert.is_truthy(tostring(warnings[1]):find("did not focus the down pane (no_neighbor)", 1, true))
    end)
  end)

  it("treats an unsignaled sentinel as a failure and skips the clear", function()
    local replies = vim.tbl_extend("force", neighbor_absent, {
      ["client.window_title.set"] = {
        result = { type = "client_window_title", changed = false, reason = "no_foreground_client" },
      },
    })
    with_herdr(replies, function(server, warnings)
      herdr.navigate("left")
      assert.same({ "pane.neighbor", "client.window_title.set" }, server:wait(2))
      assert.are.equal(1, #warnings)
      assert.is_truthy(tostring(warnings[1]):find("no_foreground_client", 1, true))
    end)
  end)

  it("times out when Herdr accepts but never answers", function()
    with_herdr({ ["pane.neighbor"] = silent }, function(server, warnings)
      assert.is_true(herdr.navigate("left"))
      assert.same({ "pane.neighbor" }, server:wait(1))

      vim.wait(4000, function()
        return #warnings > 0
      end, 20)
      assert.are.equal(1, #warnings)
      assert.is_truthy(tostring(warnings[1]):find("pane.neighbor timed out", 1, true))
    end)
  end)

  it("fails without a Herdr context", function()
    local notify = vim.notify
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.notify = function() end

    with_env({ HERDR_SOCKET_PATH = vim.NIL, HERDR_PANE_ID = "w1:p1" }, function()
      local ok, err = herdr.navigate("left")
      assert.is_false(ok)
      assert.are.equal("HERDR_SOCKET_PATH is not set", err)
    end)

    with_env({ HERDR_SOCKET_PATH = "/tmp/herdr.sock", HERDR_PANE_ID = vim.NIL }, function()
      local ok, err = herdr.navigate("left")
      assert.is_false(ok)
      assert.are.equal("HERDR_PANE_ID is not set", err)
    end)

    vim.notify = notify
  end)

  it("probes the socket for health checks", function()
    with_herdr({}, function(server)
      local context = assert(herdr.probe())
      assert.are.equal(server.socket_path, context.socket_path)
      assert.are.equal("w1:p1", context.pane_id)
    end)

    with_env({ HERDR_SOCKET_PATH = vim.fn.tempname(), HERDR_PANE_ID = "w1:p1" }, function()
      local context, err = herdr.probe()
      assert.is_nil(context)
      assert.is_truthy(tostring(err):find("connect to herdr", 1, true))
    end)
  end)
end)

describe("ghosttykit.nvim.navigation edges", function()
  local navigation

  before_each(function()
    package.loaded["ghosttykit.nvim.navigation"] = nil
    navigation = require("ghosttykit.nvim.navigation")
    config.setup({})
    vim.cmd("silent! only")
  end)

  after_each(function()
    config.setup({})
  end)

  it("hands a Neovim edge to Herdr instead of Ghostty", function()
    local replies = vim.tbl_extend("force", neighbor_present, {
      ["pane.focus_direction"] = { result = { type = "pane_focus_direction", focus = { changed = true } } },
    })
    with_herdr(replies, function(server)
      with_env({ HERDR_ENV = "1" }, function()
        navigation.navigate("left")
      end)
      assert.same({ "pane.neighbor", "pane.focus_direction" }, server:wait(2))
    end)
  end)

  it("uses the Ghostty focus call outside Herdr", function()
    local focused = nil
    package.loaded["ghosttykit.nvim.client"] = {
      focus = function(direction)
        focused = direction
        return true, nil
      end,
    }
    package.loaded["ghosttykit.nvim.navigation"] = nil
    local reloaded = require("ghosttykit.nvim.navigation")

    with_env({ HERDR_ENV = vim.NIL }, function()
      reloaded.navigate("right")
    end)

    package.loaded["ghosttykit.nvim.client"] = nil
    package.loaded["ghosttykit.nvim.navigation"] = nil
    assert.are.equal("right", focused)
  end)
end)
