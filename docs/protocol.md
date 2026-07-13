# GhosttyKit Protocol

Status: v1.

The v1 protocol is hand-maintained. Each request carries a protocol `version` field. Language implementations are maintained directly in Go, Swift, TypeScript, and Lua as needed; no schema/code generation source of truth exists.

Core invariants:

- Remote callers never provide trusted Ghostty terminal identity.
- `GTY_SOCK` is a bearer endpoint that routes to a daemon-owned bridge session.
- Lease messages require a local-only lease token.
- Request messages do not receive or require the lease token.

## Request envelope

Every request embeds this envelope:

```json
{
  "version": 1,
  "command": "doctor"
}
```

Commands that are normally fire-and-forget may set `ack` to `true` when the caller wants a definite success/failure acknowledgement.

Terminal-targeted requests carry the caller's `tty`. The daemon resolves a tty to its Ghostty terminal deterministically: through the terminal class's AppleScript `tty` property when the running Ghostty supports it (1.4.0+), otherwise through an OSC 7 rendezvous — the daemon writes a working-directory nonce to the pty device, scans Ghostty's scripting tree for the terminal reporting it, and restores the real value. Resolutions are cached per tty.

## Response envelope

Replies use:

```json
{
  "version": 1,
  "code": "ok",
  "value": "optional string"
}
```

`code` is required. `ok` means success. Any other code is failure and may include `error` for a human-readable message:

```json
{
  "version": 1,
  "code": "terminal_not_found",
  "error": "no Ghostty terminal is associated with /dev/ttys004"
}
```

See [protocol/codes.md](protocol/codes.md) for defined codes.

## Local command requests

| CLI                              | Request command        | Response behavior           | Extra fields                                             |
| -------------------------------- | ---------------------- | --------------------------- | -------------------------------------------------------- |
| `gty doctor`                     | `doctor`               | always responds             | none                                                     |
| `gty terminal-id`                | `terminal-id`          | always responds             | `tty`, optional `refresh`                                |
| `gty tab-terminal-count`         | `tab-terminal-count`   | always responds             | `tty`                                                    |
| `gty key-table activate <table>` | `key-table-activate`   | responds when `ack` is true | `tty`, `table`, optional `ack`                           |
| `gty key-table deactivate`       | `key-table-deactivate` | responds when `ack` is true | `tty`, optional `ack`                                    |
| `gty focus <direction>`          | `focus`                | responds when `ack` is true | `tty`, `direction`, optional `ack`                       |
| `gty split <direction>`          | `split`                | responds when `ack` is true | `tty`, `direction`, `cwd`, `commandText`, `focus`, `ack` |
| `gty resize <direction>`         | `resize`               | responds when `ack` is true | `tty`, `direction`, `amount`, optional `ack`             |
| `gty zoom`                       | `zoom`                 | responds when `ack` is true | `tty`, optional `ack`                                    |
| `gty input <text>`               | `input`                | responds when `ack` is true | `tty`, `text`, optional `submit`, optional `ack`         |
| `gty paste`                      | `paste`                | always responds             | `tty` optional                                           |
| `gty clear-cache`                | `clear-cache`          | responds when `ack` is true | `tty` optional, optional `ack`                           |
| `gty spawn-claim <token>`        | `spawn-claim`          | always responds             | `tty`, `spawnToken`                                      |
| `gty ssh` bridge setup           | `bridge-create`        | always responds             | `tty`                                                    |
| `gty ssh` bridge lease           | `bridge-lease`         | hold after initial response | `token`                                                  |

For `terminal-id`, `refresh: true` clears the tty's cached binding and re-resolves it.

`spawn-claim` is daemon plumbing: `ghosttykitd` mints a single-use spawn token when it creates a terminal, and the spawned process claims it to bind its TTY to the terminal the daemon created. A claim consumes the token. Bridge endpoints reject `spawn-claim` with `invalid_request`.

`amount` is exactly one of:

```json
{ "pixels": 40 }
```

or:

```json
{ "percent": 15 }
```

## Paste streaming

`paste` returns a JSON header line before streamed bytes.

Text paste:

```json
{ "version": 1, "code": "ok", "kind": "text", "bytes": 14 }
```

The daemon then streams exactly `bytes` bytes of UTF-8 text.

File paste:

```json
{
  "version": 1,
  "code": "ok",
  "kind": "files",
  "files": [
    { "fileName": "image.png", "mediaType": "image/png", "bytes": 1234 }
  ],
  "bytes": 1234
}
```

The daemon then streams each file payload in listed order. The client materializes file payloads locally.
