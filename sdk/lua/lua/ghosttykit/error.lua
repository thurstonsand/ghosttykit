---@class ghosttykit.Error
---@field code string
---@field message string?
---@field name string

local M = {}

local names = {
  protocol_version_mismatch = "VersionMismatchError",
  unknown_command = "UnknownCommandError",
  invalid_request = "InvalidRequestError",
  terminal_not_found = "TerminalNotFoundError",
  spawn_token_not_found = "SpawnTokenNotFoundError",
  ghostty_unavailable = "GhosttyUnavailableError",
  paste_empty = "PasteEmptyError",
  paste_unsupported = "PasteUnsupportedError",
  stream_failed = "StreamFailedError",
  internal_error = "InternalError",
}

local Error = {}
Error.__index = Error

function Error:__tostring()
  if self.message and self.message ~= "" then
    return self.code .. ": " .. self.message
  end
  return self.code
end

function M.new(code, message)
  return setmetatable({
    code = code,
    message = message,
    name = names[code] or "ReplyError",
  }, Error)
end

function M.from_reply(reply)
  if reply and reply.code == "ok" then
    return nil
  end
  if not reply then
    return M.new("invalid_reply", "empty reply")
  end
  return M.new(reply.code or "invalid_reply", reply.error)
end

return M
