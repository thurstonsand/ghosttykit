# gty CLI

Every terminal-scoped command targets the caller's own terminal, resolved from `--tty`, `GTY_TTY`, or the controlling terminal, in that order. Fire-and-forget commands accept `--wait` for a definite success/failure acknowledgement.

## Commands

| Command                                                                      | Behavior                                                                                                                            |
| ---------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| `gty version`                                                                | Print the client version.                                                                                                           |
| `gty doctor [--json]`                                                        | Run daemon health checks.                                                                                                           |
| `gty terminal-id [--refresh]`                                                | Print the caller's Ghostty terminal id; `--refresh` clears the cached mapping and re-resolves it.                                   |
| `gty tab-terminal-count`                                                     | Print the number of terminals in the tab.                                                                                           |
| `gty focus <left\|down\|up\|right>`                                          | Move focus between splits.                                                                                                          |
| `gty split <direction> [--cwd dir] [--command text] [--focus new\|original]` | Create a split. With `--wait`, prints the new terminal's tty (empty when the spawn claim never arrived).                            |
| `gty resize <direction> --pixels n\|--percent p`                             | Resize a split.                                                                                                                     |
| `gty zoom`                                                                   | Toggle split zoom.                                                                                                                  |
| `gty input [--submit] <text...>`                                             | Send text to a terminal as bracketed paste, joining multiple args with single spaces; `--submit` follows it with an enter keypress. |
| `gty paste [--json] [--output-dir dir]`                                      | Read the local clipboard; file content is materialized to disk.                                                                     |
| `gty key-table activate <table>` / `deactivate`                              | Activate or deactivate a Ghostty key table for the caller's terminal.                                                               |
| `gty title <text>`                                                           | Set the terminal title via OSC (no daemon involved).                                                                                |
| `gty clear-cache [--all]`                                                    | Drop the caller's cached tty mapping, or all mappings.                                                                              |
| `gty ssh [flags] host [-- remote command]`                                   | SSH with a GhosttyKit bridge; see `docs/ssh.md`.                                                                                    |
| `gty spawn-claim <token>` (hidden)                                           | Daemon plumbing: binds the caller's tty to a daemon-spawned terminal. Invoked by `ghosttykitd`'s spawn wrapper, not by hand.        |

## Exit codes

`gty` keeps process exit codes intentionally small.

| Exit code | Meaning                                                                |
| --------- | ---------------------------------------------------------------------- |
| `0`       | Success.                                                               |
| `1`       | Request failed or daemon/client error.                                 |
| `2`       | Command-line usage error, or clipboard has no supported paste content. |

Protocol response codes are separate from CLI process exit codes. See `docs/protocol/codes.md` for daemon response codes.
