# GhosttyKit Protocol Codes

Every response includes a required `code`.

## Success

| Code | Meaning            |
| ---- | ------------------ |
| `ok` | Request succeeded. |

## Errors

| Code                        | Meaning                                                                |
| --------------------------- | ---------------------------------------------------------------------- |
| `protocol_version_mismatch` | Request protocol version is unsupported.                               |
| `unknown_command`           | Request command is not recognized.                                     |
| `invalid_request`           | Request shape or field value is invalid.                               |
| `terminal_not_found`        | No Ghostty terminal matches the requested local TTY or bridge session. |
| `spawn_token_not_found`     | Spawn token is unknown, already claimed, or expired.                   |
| `ghostty_unavailable`       | Ghostty cannot be reached or controlled.                               |
| `paste_empty`               | Clipboard has no supported paste content.                              |
| `paste_unsupported`         | Clipboard content exists but no supported representation is available. |
| `stream_failed`             | Streamed content could not be sent completely.                         |
| `internal_error`            | Unexpected daemon failure.                                             |

Protocol codes are separate from CLI process exit codes. See `docs/cli.md` for `gty` exit codes.
