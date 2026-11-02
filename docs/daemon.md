# ghosttykitd

`ghosttykitd` is the macOS daemon that owns local Ghostty control, pasteboard access, and the local Unix socket endpoint used by `gty`.

## Socket selection

By default the daemon listens on:

```text
~/.local/run/ghosttykit/ghosttykitd.sock
```

For development and integration tests, set `GTY_SOCK` before starting both the daemon and client.

## TTY resolution

A request names its terminal with an explicit `tty` or the caller's own `callerTty`; see [protocol.md](protocol.md). The daemon maps that tty to its Ghostty terminal by scanning Ghostty's scripting tree for the terminal whose `tty` AppleScript property matches. Bindings are cached per tty (12h), and every cache hit is verified before use with one Apple Event that reads the cached terminal's `tty` through its full window → tab → terminal path. That read fails if the terminal closed or moved to another tab or window, and returns a different tty if the id now names something else; either way the daemon rescans and re-caches. A closed terminal's recycled pty or a moved tab therefore never reaches a command. A split caches the new terminal's binding from the split reply, overwriting any entry left on a recycled pty. Nothing retries: a command that fails mid-action fails.

`gty doctor` reports the running Ghostty's version and fails when it is older than 1.4.0, the first release with the `tty` property. It also warns when the daemon lacks Accessibility, which only `resize --percent` needs; see [tcc-macos.md](tcc-macos.md).

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
| split terminal tty                                   | `/dev/dry-run-split`     |
| Ghostty version                                      | `1.4.0-dry-run`          |
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

If `GTY_SOCK` is unset, it starts the daemon on a temporary socket and cleans it up afterward. Set `GTY_BIN`, `GHOSTTYKITD_BIN`, or `GTY_SOCK` to override defaults. It refuses a dry-run endpoint, resolves the invoking terminal's own tty through Ghostty's `tty` property (so it must run from a real Ghostty terminal, or `GTY_SMOKE_TTY` must name one), and exercises real daemon behavior: doctor, terminal-id cache refresh, tab count, pasteboard streaming, key-table activation/deactivation, split creation with its TTY reply, split overwrite of a stale cache binding, submitted typed input, focus movement, pixel and percent resize, zoom toggling, and cache clearing. It also checks addressing: the main daemon rejects a request naming no terminal, and with `--bridge` a remote command without a pty acts on the bridge's terminal while an explicit `--tty` is rejected.

This test is intentionally mutating. It changes the pasteboard temporarily and creates a short-lived split in the focused Ghostty tab.
