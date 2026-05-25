# GhosttyKit

GhosttyKit is a Ghostty companion toolkit for macOS-local terminal control, editor navigation, SSH-bridged commands, and clipboard paste workflows.

- CLI: `gty`
- Daemon: `ghosttykitd`
- Neovim plugin: `nvim/`
- Pi paste extension: `pi/pi-paste/`

Status: extraction in progress. The Go `gty` CLI, Go SDK, Swift daemon, SSH bridge flow, and release workflow are present; editor, Homebrew, and extension packaging work continues under `docs/designs/01-ghosttykit-standalone.md`.

## Development

Project-local tool versions live in `mise.toml`.

```sh
mise install    # install project tools
just build      # build binaries
just check      # format, lint, typecheck, test, build, and validate packaging/CI config
just --list
```

Component recipes are available as `*-go`, `*-swift`, `*-pi`, and `*-nvim` variants.
