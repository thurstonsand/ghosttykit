local M = {}

local defaults = {
  key_table = "nvim",
  focused = true,
  float_win_behavior = "previous",
  notify_errors = false,
}

local valid_float_win_behavior = {
  previous = true,
  mux = true,
}

local current = vim.deepcopy(defaults)

local function validate(opts)
  opts = opts or {}
  vim.validate("opts", opts, "table", true)
  if opts.key_table ~= nil then
    vim.validate("key_table", opts.key_table, "string")
  end
  if opts.focused ~= nil then
    vim.validate("focused", opts.focused, "boolean")
  end
  if opts.float_win_behavior ~= nil then
    vim.validate("float_win_behavior", opts.float_win_behavior, "string")
    if not valid_float_win_behavior[opts.float_win_behavior] then
      error("float_win_behavior must be 'previous' or 'mux'")
    end
  end
  if opts.notify_errors ~= nil then
    vim.validate("notify_errors", opts.notify_errors, "boolean")
  end
end

function M.setup(opts)
  validate(opts)
  current = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  return current
end

function M.get()
  return current
end

function M.defaults()
  return vim.deepcopy(defaults)
end

function M.validate(opts)
  return validate(opts)
end

return M
