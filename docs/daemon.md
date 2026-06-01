# ghosttykitd

`ghosttykitd` is the macOS daemon that owns local Ghostty control, pasteboard access, and the local Unix socket endpoint used by `gty`.

## Socket selection

By default the daemon listens on:

```text
~/.local/run/ghosttykit/ghosttykitd.sock
```

For development and integration tests, set `GTY_SOCK` before starting both the daemon and client.

## Dry run mode

`ghosttykitd --dry-run` starts the daemon normally but replaces Ghostty AppleScript calls with deterministic mock values. Pasteboard reads still use the real macOS pasteboard.

Dry-run Ghostty values:

| Operation                                     | Value              |
| --------------------------------------------- | ------------------ |
| focused terminal id                           | `dry-run-terminal` |
| focused window id                             | `dry-run-window`   |
| focused tab id                                | `dry-run-tab`      |
| tab terminal count                            | `1`                |
| window width/height for percent resize        | `1000`             |
| key table, focus, split, resize, zoom actions | no-op success      |

Example:

```sh
sock=/tmp/ghosttykitd.sock
GTY_SOCK=$sock ghosttykitd --dry-run &
GTY_SOCK=$sock GTY_TTY=/dev/dryrun gty doctor
```

## Real daemon smoke test

With Ghostty focused on the starting window, run:

```sh
just smoke-real-daemon
```

To run the same checks through a daemon-owned bridge socket, run:

```sh
just smoke-real-daemon --bridge
```

If `GTY_SOCK` is unset, it starts the daemon on a temporary socket and cleans it up afterward. Set `GTY_BIN`, `GHOSTTYKITD_BIN`, or `GTY_SOCK` to override defaults. It refuses a dry-run endpoint, binds a temporary synthetic TTY to the focused terminal, and exercises real daemon behavior: doctor, terminal-id cache refresh, tab count, pasteboard streaming, key-table activation/deactivation, split creation, focus movement, resize, zoom toggling, and cache clearing.

This test is intentionally mutating. It changes the pasteboard temporarily and creates a short-lived split in the focused Ghostty tab.
