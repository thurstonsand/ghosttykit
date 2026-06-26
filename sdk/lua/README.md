# GhosttyKit Lua SDK

`ghosttykit` is the Lua client library for talking to `ghosttykitd` and GhosttyKit bridge sockets. Use it from Neovim plugins, Lua scripts, or LuaRocks-based tools that need to control Ghostty through GhosttyKit.

## Installation

Published package installation is coming next.

The SDK supports two runtimes:

- Neovim: uses `vim.uv` and `vim.json`.
- LuaJIT/LuaRocks: uses `luv` and `dkjson`.

## Usage

Create a client and call GhosttyKit commands:

```lua
local ghosttykit = require("ghosttykit")

local client = ghosttykit.client()
local status, err = client:doctor()

if err then
  error(tostring(err))
end

print(status.healthy)
```

By default, the client connects to the standard GhosttyKit socket. Pass `socket_path` to target another daemon or bridge socket:

```lua
local client = ghosttykit.client({
  socket_path = "/path/to/ghosttykit.sock",
})
```

## Commands

Commands are grouped by domain. Most methods return `value, err`; methods that only need acknowledgement return `ok, err` when `ack = true`, or send a notification without waiting when `ack` is omitted.

```lua
client:doctor()
client.terminal:id({ focused = true })
client.terminal:count({ focused = true })
client.terminal:clear_cache({ ack = true })
client.key_table:activate({ name = "nvim", focused = true, ack = true })
client.key_table:deactivate({ focused = true, ack = true })
client.layout:focus({ direction = "left", focused = true, ack = true })
client.layout:split({ direction = "right", cwd = vim.fn.getcwd(), focus = true, ack = true })
client.layout:resize({ direction = "right", pixels = 10, ack = true })
client.layout:zoom({ ack = true })
client.paste:get()
client.bridge:create({ focused = true })
```

Paste handles can read text, read file contents, or save pasted content to disk:

```lua
local paste = assert(client.paste:get())
local saved = assert(paste:save({ dir = "/tmp/ghosttykit-paste" }))
print(saved[1].path)
```

## Low-level protocol escape hatches

Raw request builders are available through `ghosttykit.protocol`, and clients expose protocol reply modes through `client.raw`:

```lua
local request = ghosttykit.protocol.focus({ direction = "left", ack = true })
local reply, err = client.raw:call(request)

local stream, stream_err = client.raw:stream(ghosttykit.protocol.paste())
local held, hold_err = client.raw:hold(ghosttykit.protocol.bridge_lease(token))
```

## Errors

Errors are returned as values, not thrown:

```lua
local ok, err = client.layout:focus({ direction = "left", ack = true })
if not ok then
  vim.notify(err.message or err.code, vim.log.levels.ERROR)
end
```

Each error has:

- `code`: protocol or transport error code.
- `message`: optional human-readable detail.
- `name`: stable error name for callers that prefer names over codes.

## Development

Install the SDK from a local checkout:

```sh
cd sdk/lua
luarocks make --tree ../../.luarocks --lua-version 5.1 ghosttykit-scm-1.rockspec
```

Run the development checks:

```sh
just install-deps
just check
```
