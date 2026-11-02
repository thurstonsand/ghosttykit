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

Terminal-targeted requests name their terminal with `tty` or `callerTty`. `tty` is an explicit target: the client was told which terminal to act on. `callerTty` is the terminal the client detected for itself. The main daemon uses `tty` when present, else `callerTty`, and rejects a request with neither as `invalid_request`. It resolves a tty to its Ghostty terminal through the terminal class's AppleScript `tty` property and caches resolutions per tty, verifying each cached resolution with Ghostty before use.

A bridge daemon acts only on the terminal that created it. It ignores `callerTty`, which names a terminal on the remote host, and rejects `tty` as `invalid_request`, so a remote command needs no pty and an explicit target is never silently dropped.

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

| CLI                              | Request command        | Response behavior           | Extra fields                                              |
| -------------------------------- | ---------------------- | --------------------------- | --------------------------------------------------------- |
| `gty doctor`                     | `doctor`               | always responds             | none                                                      |
| `gty terminal-id`                | `terminal-id`          | always responds             | target, optional `refresh`                                |
| `gty tab-terminal-count`         | `tab-terminal-count`   | always responds             | target                                                    |
| `gty key-table activate <table>` | `key-table-activate`   | responds when `ack` is true | target, `table`, optional `ack`                           |
| `gty key-table deactivate`       | `key-table-deactivate` | responds when `ack` is true | target, optional `ack`                                    |
| `gty focus <direction>`          | `focus`                | responds when `ack` is true | target, `direction`, optional `ack`                       |
| `gty split <direction>`          | `split`                | responds when `ack` is true | target, `direction`, `cwd`, `commandText`, `focus`, `ack` |
| `gty resize <direction>`         | `resize`               | responds when `ack` is true | target, `direction`, `amount`, optional `ack`             |
| `gty zoom`                       | `zoom`                 | responds when `ack` is true | target, optional `ack`                                    |
| `gty input <text>`               | `input`                | responds when `ack` is true | target, `text`, optional `submit`, optional `ack`         |
| `gty paste`                      | `paste`                | always responds             | none                                                      |
| `gty clear-cache`                | `clear-cache`          | responds when `ack` is true | target, or `all: true`; optional `ack`                    |
| `gty ssh` bridge setup           | `bridge-create`        | always responds             | target                                                    |
| `gty ssh` bridge lease           | `bridge-lease`         | hold after initial response | `token`                                                   |

"target" is `tty` or `callerTty`, as above.

For `terminal-id`, `refresh: true` clears the tty's cached binding and re-resolves it.

`clear-cache` drops the target's cached binding, or every binding with `all: true`. On a bridge the target is the bridge's own local tty.

An acknowledged `split` replies with the new terminal's tty in `value`. Over a bridge that tty names a local terminal, which the bridge does not accept as a target.

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
