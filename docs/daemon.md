# ghosttykitd

`ghosttykitd` is the macOS daemon that owns local Ghostty control, pasteboard access, and the local Unix socket endpoint used by `gty`.

## Socket selection

By default the daemon listens on:

```text
~/.local/run/ghosttykit/ghosttykitd.sock
```

For development and integration tests, set `GTY_SOCK` before starting both the daemon and client.

## TTY resolution

The daemon maps a caller's tty to its Ghostty terminal. When the running Ghostty exposes the terminal `tty` AppleScript property (1.4.0+, probed once at first resolution), it scans the scripting tree for the matching terminal directly. On older Ghostty it performs an OSC 7 rendezvous: it writes a working-directory nonce straight to the pty device, scans for the terminal whose `working directory` reports the nonce, and restores the real value (read from the tty's foreground process). Bindings are cached per tty (12h). A retry-safe action that fails because its cached terminal no longer exists clears the binding, re-resolves, and retries once. Multi-event operations such as input and split fail without replay.

Observable side effect of a rendezvous: the pane's reported working directory is briefly a `/gty-rendezvous/<uuid>` path; on panes that have never set a title, Ghostty's pwd-derived title flashes it for the same instant.

## Spawn claims

When the daemon creates a terminal (`split`), it wraps the spawned command so the terminal's first act is a `gty spawn-claim` that binds its TTY to the exact terminal the daemon created — a warm cache entry with no resolution cost.

## Bridge sessions

For `gty ssh`, the daemon creates a per-session bridge: a daemon-owned Unix socket bound to one Ghostty terminal, kept alive by a local lease connection and destroyed when the lease closes. See `docs/ssh.md`.

## Dry run mode

`ghosttykitd --dry-run` starts the daemon normally but replaces Ghostty control calls with deterministic mock values. Pasteboard reads still use the real macOS pasteboard.

Dry-run Ghostty values:

| Operation                                            | Value                    |
| ---------------------------------------------------- | ------------------------ |
| resolved terminal id                                 | `dry-run-terminal`       |
| resolved window id                                   | `dry-run-window`         |
| resolved tab id                                      | `dry-run-tab`            |
| tab terminal count                                   | `1`                      |
| split terminal id                                    | `dry-run-split-terminal` |
| window width/height for percent resize               | `1000`                   |
| key table, focus, split, resize, zoom, input actions | no-op success            |

Example:

```sh
sock=/tmp/ghosttykitd.sock
GTY_SOCK=$sock ghosttykitd --dry-run &
GTY_SOCK=$sock GTY_TTY=/dev/dryrun gty doctor
```

## Real daemon smoke test

With Ghostty focused on the starting window, run:

```sh
mise run smoke-real-daemon
```

To run the same checks through a daemon-owned bridge socket, run:

```sh
mise run smoke-real-daemon --bridge
```

If `GTY_SOCK` is unset, it starts the daemon on a temporary socket and cleans it up afterward. Set `GTY_BIN`, `GHOSTTYKITD_BIN`, or `GTY_SOCK` to override defaults. It refuses a dry-run endpoint, resolves the invoking terminal's own tty through the deterministic resolution path (so it must run from a real Ghostty terminal, or `GTY_SMOKE_TTY` must name one), and exercises real daemon behavior: doctor, terminal-id cache refresh, tab count, pasteboard streaming, key-table activation/deactivation, split creation with spawn-claimed TTY reply, claim overwrite of a stale cache binding, submitted typed input, focus movement, resize, zoom toggling, and cache clearing.

This test is intentionally mutating. It changes the pasteboard temporarily and creates a short-lived split in the focused Ghostty tab.
