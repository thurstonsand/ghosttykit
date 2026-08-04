<!-- markdownlint-disable MD024 -->

# Release notes

## 0.6.0

One keymap across Ghostty splits, Herdr panes, and Neovim windows.

### Added

- `gty herdr attach <host>` runs a remote Herdr session with bare `ctrl+h/j/k/l` navigation that crosses every layer: Neovim windows first, then Herdr panes, then Ghostty splits. Setup is four Herdr `[[keys.command]]` bindings and the Ghostty key table; see `docs/ssh.md`.
- `gty herdr navigate <direction>` decides which layer moves, from inside the remote pane. Called by Herdr's keybindings, not by hand.
- `ghosttykit.nvim` speaks Herdr's socket directly when running inside a Herdr pane, so a Neovim edge costs no process spawn.

### Changed

- The Ghostty key table is now named `bypass`, not `nvim`. It is shared by the Neovim plugin and `gty herdr attach`.
- Inside Herdr, `ghosttykit.nvim` leaves key-table ownership to `gty herdr attach`, which holds it for the whole session.

### Fixed

- A `gty ssh` session that dies while a remote full-screen application is running no longer leaves the local terminal holding that application's modes.
- Nightly versions sort above the stable release they were built on, so channels are comparable again.

## 0.5.0

Remote bootstrap that works from a real install.

### Added

- `gty ssh` now bootstraps a remote host by downloading the `gty` asset from the release the local binary came from, so Homebrew and `go install` builds can reach Linux hosts instead of only source checkouts.
- Release archives for Linux `amd64` and `arm64` carrying `gty` alone, and an `on_linux` branch in the Homebrew formula.
- `go install github.com/thurstonsand/ghosttykit/cli/gty@vX.Y.Z` binaries include their release tag from build info, so they report a real version and bootstrap like any other release build.

### Changed

- Homebrew moved to the shared `thurstonsand/tap`: `brew install thurstonsand/tap/ghosttykit`.
- Bootstrap installs to `${XDG_DATA_HOME:-$HOME/.local/share}/ghosttykit/bin/gty` instead of the remote `PATH`. A `gty` you installed yourself is preferred and never overwritten while its version matches.

### Fixed

- A stale `gty` on the remote `PATH` no longer triggers a fresh bootstrap on every connection.
- Hosts configured with `RequestTTY` in `ssh_config` no longer corrupt GhosttyKit's own SSH probes; version and `remote-init` replies parse again.
- Remote commands run under `/bin/sh`, so accounts whose login shell is csh or tcsh can be bootstrapped.

## 0.4.0

Deterministic terminal targeting and hardened Ghostty control.

### Added

- Added `gty input` and SDK input APIs for sending text to a terminal, with optional Enter submission.
- Added spawn-token binding so daemon-created splits report and cache their exact tty without relying on focus timing.
- Added deterministic tty-to-terminal resolution through Ghostty's scripting `tty` property when available, with an OSC 7 rendezvous fallback on older Ghostty versions.

### Changed

- Replaced Ghostty AppleScript source execution with direct Apple Events, cutting median latency roughly in half for representative operations in benchmarks (focused context: 53.3→25.0 ms; perform action: 16.7→8.3 ms), with substantially lower tail latency.
- Removed `focused` targeting from the protocol, CLI integrations, SDKs, and Neovim plugin. Terminal-targeted raw requests now require `tty`; high-level SDK clients derive it from `GTY_TTY` or the controlling terminal when omitted.
- Moved the Go CLI and SDK into one root module at `github.com/thurstonsand/ghosttykit`.

### Fixed

- Prevented focus races from binding a tty to the wrong Ghostty terminal.
- Retry-safe actions now clear and recover stale terminal bindings without replaying partial input or split operations.
- Fixed daemon-installed splits failing to find the matching `gty` executable.

## 0.3.0

SDK and Pi paste expansion.

### Added

- Added the `@thurstonsand/ghosttykit` TypeScript SDK for JavaScript and TypeScript integrations.
- Added `@thurstonsand/pi-paste`, a Pi extension that pastes local Mac clipboard text and files into remote Pi sessions running through `gty ssh`.
- Added higher-level domain clients for Go, Lua, and TypeScript callers, including terminal, layout, key-table, bridge, and paste operations.

### Changed

- Reworked SDK APIs around the new domain clients.

### Fixed

- Lua paste bodies now stream correctly through the transport instead of being buffered in memory first.

## 0.2.1

Release process hardening.

### Changed

- Stable GitHub releases now use the matching `RELEASE.md` entry as the release body when the tag-triggered workflow creates the release.
- Documented the stable release flow as tag-driven across GitHub releases, Homebrew, Lua mirrors, and LuaRocks.
- Added the `release-all` skill for coordinating GhosttyKit releases.

## 0.2.0

Initial GhosttyKit release.

### Added

- `ghosttykitd`, the macOS daemon that owns Ghostty AppleScript control, terminal identity caching, key-table activation, pane layout operations, paste streaming, and daemon-owned SSH bridge sockets.
- `gty`, the GhosttyKit CLI for checking daemon health, moving focus, splitting and resizing Ghostty panes, switching key tables, pasting clipboard contents, and opening bridged SSH sessions.
- The Go SDK and protocol model used by `gty`, including request framing, response-code handling, reply modes, and daemon socket discovery.
- `gty ssh`, which bootstraps remote `gty` binaries when needed and exposes the originating local Ghostty surface to remote commands through Unix-socket reverse forwarding.
- The Lua SDK as `ghosttykit`, with protocol helpers, request framing, GhosttyKit socket discovery, and both LuaRocks/luv and Neovim/vim.uv transports.
- The `ghosttykit.nvim` plugin for Neovim-to-Ghostty split navigation, including lazy.nvim metadata, default `<C-h/j/k/l>` mappings, `<Plug>` mappings, TTY discovery, key-table activation, and `:checkhealth ghosttykit`.
- Homebrew stable and nightly packaging, including signed/notarized daemon app bundles, `brew services` integration, and `gty doctor` diagnostics for socket and Automation readiness.
- Generated `ghosttykit.lua` and `ghosttykit.nvim` mirror repositories from the monorepo, with stable tags and moving nightly tags.
