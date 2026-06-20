local M = {}

function M.auto()
  local vim_runtime = rawget(_G, "vim")
  if vim_runtime and vim_runtime.json then
    return {
      encode = vim_runtime.json.encode,
      decode = vim_runtime.json.decode,
    }
  end

  local ok, dkjson = pcall(require, "dkjson")
  if ok then
    return {
      encode = dkjson.encode,
      decode = function(input)
        local value, position, err = dkjson.decode(input)
        if err then
          error(err .. " at " .. tostring(position))
        end
        return value
      end,
    }
  end

  error("ghosttykit requires vim.json or dkjson")
end

return M
