# gty CLI

## Exit codes

`gty` keeps process exit codes intentionally small.

| Exit code | Meaning                                                                |
| --------- | ---------------------------------------------------------------------- |
| `0`       | Success.                                                               |
| `1`       | Request failed or daemon/client error.                                 |
| `2`       | Command-line usage error, or clipboard has no supported paste content. |

Protocol response codes are separate from CLI process exit codes. See `docs/protocol/codes.md` for daemon response codes.
