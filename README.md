# GhosttyKit

GhosttyKit is a Ghostty companion toolkit for macOS-local terminal control, editor navigation, SSH-bridged commands, and clipboard paste workflows.

- CLI: `gty`
- Daemon: `ghosttykitd`
- Neovim plugin: `nvim/`
- Pi paste extension: `pi/pi-paste/`

Status: design and extraction skeleton. The current design lives in `docs/designs/01-ghosttykit-standalone.md`.

## Development

```sh
just build      # build binaries
just check      # format, lint, typecheck, and test everything available
just --list
```

Component recipes are available as `*-go`, `*-swift`, `*-pi`, and `*-nvim` variants.
