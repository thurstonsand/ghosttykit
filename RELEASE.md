<!-- markdownlint-disable MD024 -->

# Release notes

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
