# AGENTS.md

## Mission

GhosttyKit is a Ghostty terminal companion toolkit.

## Project Context

Use @CONTEXT.md for terminology and architecture vocabulary.

## Working Rules

- Preserve the established component boundaries. Moving code across them requires a concrete reason.
- Do not keep legacy compatibility unless explicitly ordered -- prefer breaking changes. For now, GhosttyKit owns both sides of every internal interface; make hard breaks instead of compatibility shims unless this file is updated to say otherwise.
- Prefer direct, boring implementations over abstraction.
- When updating documentation/comments, keep it current, as if the code was always written that way. Don't include historical context unless the document is specifically historical.
- Do not add comments that restate code. Use comments only for non-obvious decisions.

## Go Style

- Prefer top-down file organization: exported entry points and primary behavior first, with helper functions and private supporting types after their first use where practical.
- Keep exported types near the top of the file when they define the package API.
- Do not run `gofmt` directly. Format Go through the component `just fmt` recipe so the configured `goimports` and `gofumpt` behavior is used.

## Repository Layout

- `cli/gty/`: Go CLI. Owns user-facing commands, local daemon calls, SSH wrapper behavior, and remote helper commands.
- `sdk/go/`: Go client/protocol package. Shared Go code for request framing, socket selection, protocol types, and reusable client behavior.
- `daemon/ghosttykitd/`: Swift macOS daemon. Owns Ghostty control, pasteboard access, local sockets, and daemon-managed bridge lifecycle.
- `nvim/`: Neovim plugin. Coordinates editor split navigation with Ghostty pane focus and activates/deactivates the Ghostty Neovim key table.
- `pi/pi-paste/`: Pi paste extension npm package. Pi-facing Alt-v paste flow backed by `gty paste`, including remote bridge support through normal CLI behavior.
- `homebrew/`: Homebrew packaging material. macOS install path for `gty`, `ghosttykitd`, and daemon service management.
- `docs/`: public docs and design records.

## Commands

Root commands:

```sh
just --list
just fmt
just lint
just typecheck
just test
just build
just check
```

Component commands:

```sh
just -f cli/gty/justfile check
just -f sdk/go/justfile check
just -f daemon/ghosttykitd/justfile check
just -f nvim/justfile check
just -f pi/pi-paste/justfile check
```

`pi/pi-paste` checks require `node_modules`. Use:

```sh
just install-deps-pi
```

if you run into dependency issues.
