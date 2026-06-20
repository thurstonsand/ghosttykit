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
local reply, err = client:doctor()

if err then
  error(tostring(err))
end

print(reply.healthy)
```

By default, the client connects to the standard GhosttyKit socket. Pass `socket_path` to target another daemon or bridge socket:

```lua
local client = ghosttykit.client({
  socket_path = "/path/to/ghosttykit.sock",
})
```

## Commands

Most methods return `reply, err`. Methods that only need acknowledgement return `ok, err` when `ack = true`, or send a notification without waiting when `ack` is omitted.

```lua
client:doctor()
client:terminal_id({ focused = true })
client:tab_terminal_count({ focused = true })
client:key_table_activate({ table = "nvim", focused = true, ack = true })
client:key_table_deactivate({ focused = true, ack = true })
client:focus({ direction = "left", focused = true, ack = true })
client:split({ direction = "right", cwd = vim.fn.getcwd(), focus = true, ack = true })
client:resize({ direction = "right", amount = 10, ack = true })
client:zoom({ ack = true })
client:paste({ focused = true })
client:bridge_create({ focused = true })
client:bridge_lease(token)
```

For lower-level integrations, request builders are available through `ghosttykit.protocol`:

```lua
local request = ghosttykit.protocol.focus({ direction = "left", ack = true })
local reply, err = client:call(request)
```

## Errors

Errors are returned as values, not thrown:

```lua
local ok, err = client:focus({ direction = "left", ack = true })
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
