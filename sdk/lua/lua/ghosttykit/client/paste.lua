local protocol = require("ghosttykit.protocol")
local errors = require("ghosttykit.error")

local M = {}

local PasteClient = {}
PasteClient.__index = PasteClient

local Paste = {}
Paste.__index = Paste

local ExactReader = {}
ExactReader.__index = ExactReader

local function valid_byte_count(bytes, message)
  local count = tonumber(bytes)
  if not count or count < 0 or count ~= math.floor(count) then
    return nil, errors.new("invalid_reply", message)
  end
  return count, nil
end

local function basename(path)
  return tostring(path or ""):gsub("\\", "/"):match("[^/]+$")
end

local function split_extension(name)
  local base, ext = name:match("^(.*)(%.[^%.]*)$")
  if base and base ~= "" then
    return base, ext
  end
  return name, ""
end

local function sanitize_filename_part(value, fallback)
  value = tostring(value or ""):gsub('[<>:"/\\|%?%*%c]', "_"):gsub("^%s+", ""):gsub("%s+$", "")
  if value == "" or value == "." or value == ".." then
    return fallback
  end
  return value
end

local function random_suffix()
  local file = io.open("/dev/urandom", "rb")
  if file then
    local bytes = file:read(8)
    file:close()
    if bytes and #bytes == 8 then
      return (bytes:gsub(".", function(char)
        return string.format("%02x", string.byte(char))
      end))
    end
  end
  return string.format("%x%x", os.time(), math.random(0, 0xfffffff))
end

local function unique_text_file_name()
  return "pasted-text-" .. random_suffix() .. ".txt"
end

local function unique_file_name(file_info)
  local name = basename(file_info.file_name)
  if name and name ~= "" and name ~= "." and name ~= ".." then
    local base, ext = split_extension(name)
    return sanitize_filename_part(base, "pasted-file") .. "-" .. random_suffix() .. sanitize_filename_part(ext, "")
  end
  return "pasted-file-" .. random_suffix()
end

local function join_path(dir, name)
  if dir:sub(-1) == "/" then
    return dir .. name
  end
  return dir .. "/" .. name
end

local function uv_runtime()
  local vim_runtime = rawget(_G, "vim")
  if vim_runtime and vim_runtime.uv then
    return vim_runtime.uv
  end
  local ok, uv = pcall(require, "luv")
  if ok then
    return uv
  end
  return nil
end

local function mkdir_p(path)
  local uv = uv_runtime()
  if not uv or path == "" or path == "." then
    return true, nil
  end

  local current = path:sub(1, 1) == "/" and "/" or ""
  for part in path:gmatch("[^/]+") do
    if current == "" or current == "/" then
      current = current .. part
    else
      current = current .. "/" .. part
    end

    local stat = uv.fs_stat(current)
    if stat then
      if stat.type ~= "directory" then
        return nil, errors.new("stream_failed", current .. " is not a directory")
      end
    else
      local ok, mkdir_err = uv.fs_mkdir(current, 448)
      if not ok and not uv.fs_stat(current) then
        return nil, errors.new("stream_failed", mkdir_err)
      end
    end
  end
  return true, nil
end

local function normalize_file(file)
  local bytes, err =
    valid_byte_count(file.bytes, "clipboard file " .. tostring(file.fileName or "") .. " has invalid byte count")
  if err then
    return nil, err
  end
  return {
    file_name = file.fileName,
    media_type = file.mediaType,
    bytes = bytes,
    source = file.source,
  },
    nil
end

function ExactReader.new(body)
  return setmetatable({
    body = body,
    pending = "",
  }, ExactReader)
end

function ExactReader:take(max_bytes)
  if max_bytes <= 0 then
    return "", nil
  end

  if self.pending ~= "" then
    local chunk = self.pending:sub(1, max_bytes)
    self.pending = self.pending:sub(#chunk + 1)
    return chunk, nil
  end

  local chunk, err
  repeat
    chunk, err = self.body:read()
    if err then
      return nil, errors.new("stream_failed", err)
    end
    if not chunk then
      return nil, errors.new("invalid_reply", "paste stream ended before expected byte count")
    end
  until chunk ~= ""

  if #chunk > max_bytes then
    self.pending = chunk:sub(max_bytes + 1)
    return chunk:sub(1, max_bytes), nil
  end
  return chunk, nil
end

function ExactReader:read_bytes(bytes)
  local chunks = {}
  local remaining = bytes
  while remaining > 0 do
    local chunk, err = self:take(remaining)
    if err then
      return nil, err
    end
    remaining = remaining - #chunk
    table.insert(chunks, chunk)
  end
  return table.concat(chunks), nil
end

function ExactReader:write_file(path, bytes)
  local file, open_err = io.open(path, "wb")
  if not file then
    return nil, errors.new("stream_failed", open_err)
  end

  local remaining = bytes
  while remaining > 0 do
    local chunk, err = self:take(remaining)
    if err then
      file:close()
      os.remove(path)
      return nil, err
    end

    local ok, write_err = file:write(chunk)
    if not ok then
      file:close()
      os.remove(path)
      return nil, errors.new("stream_failed", write_err)
    end
    remaining = remaining - #chunk
  end

  file:close()
  return path, nil
end

function Paste.new(header, body)
  local bytes, err = valid_byte_count(header.bytes, "paste has invalid byte count")
  if err then
    return nil, err
  end

  local files = {}
  for _, file in ipairs(header.files or {}) do
    local normalized
    normalized, err = normalize_file(file)
    if err then
      return nil, err
    end
    table.insert(files, normalized)
  end

  return setmetatable({
    kind = header.kind,
    bytes = bytes,
    files = files,
    state = "pending",
    reader = ExactReader.new(body),
    body = body,
  }, Paste)
end

local function consume(paste, fn)
  if paste.state ~= "pending" then
    return nil, errors.new("paste_consumed", "paste stream has already been consumed")
  end
  paste.state = "consuming"
  local result, err = fn()
  paste.state = "consumed"
  paste:close()
  return result, err
end

function Paste:text()
  if self.kind ~= "text" then
    return nil, errors.new("invalid_request", "paste is not text")
  end
  return consume(self, function()
    return self.reader:read_bytes(self.bytes)
  end)
end

function Paste:contents()
  if self.kind ~= "files" then
    return nil, errors.new("invalid_request", "paste is not files")
  end
  return consume(self, function()
    local contents = {}
    for _, file in ipairs(self.files) do
      local data, err = self.reader:read_bytes(file.bytes)
      if err then
        return nil, err
      end
      table.insert(contents, {
        file_name = file.file_name,
        media_type = file.media_type,
        bytes = file.bytes,
        source = file.source,
        data = data,
      })
    end
    return contents, nil
  end)
end

local function save_entry(reader, dir, file_info, file_name)
  local path = join_path(dir, file_name)
  local saved_path, err = reader:write_file(path, file_info.bytes)
  if err then
    return nil, err
  end
  return {
    path = saved_path,
    file_name = file_info.file_name,
    media_type = file_info.media_type,
    bytes = file_info.bytes,
    source = file_info.source,
  },
    nil
end

function Paste:save(opts)
  opts = opts or {}
  local dir = opts.dir or "."
  local _, mkdir_err = mkdir_p(dir)
  if mkdir_err then
    return nil, mkdir_err
  end

  return consume(self, function()
    local saved = {}
    if self.kind == "text" then
      local file = { media_type = "text/plain", bytes = self.bytes, source = "pasteboard-text" }
      local entry, err = save_entry(self.reader, dir, file, unique_text_file_name())
      if err then
        return nil, err
      end
      table.insert(saved, entry)
      return saved, nil
    end

    if self.kind ~= "files" then
      return nil, errors.new("invalid_reply", "paste has unknown kind")
    end

    for _, file in ipairs(self.files) do
      local entry, err = save_entry(self.reader, dir, file, unique_file_name(file))
      if err then
        return nil, err
      end
      table.insert(saved, entry)
    end
    return saved, nil
  end)
end

function Paste:close()
  self.body:close()
end

function PasteClient:get(opts)
  local result, err = self.ops.stream(self.client, protocol.paste(opts))
  if err then
    return nil, err
  end
  if not result then
    return nil, errors.new("invalid_reply", "empty paste reply")
  end
  return Paste.new(result.header or {}, result.body)
end

function M.new(client, ops)
  return setmetatable({ client = client, ops = ops }, PasteClient)
end

return M
