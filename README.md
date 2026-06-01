# GhosttyKit

GhosttyKit is a Ghostty companion toolkit for macOS-local terminal control, editor navigation, SSH-bridged commands, and clipboard paste workflows.

- CLI: `gty`
- Daemon: `ghosttykitd`
- Neovim plugin: `nvim/`
- Pi paste extension: `pi/pi-paste/`

Status: extraction in progress. The Go `gty` CLI, Go SDK, Swift daemon, SSH bridge flow, and release workflow are present; editor, Homebrew, and extension packaging work continues under `docs/designs/01-ghosttykit-standalone.md`.

## Install

GhosttyKit is distributed for macOS through the `thurstonsand/homebrew-ghosttykit` Homebrew tap.

Nightly builds track recent commits on `main`:

```sh
brew install thurstonsand/ghosttykit/ghosttykit-nightly
```

Start Ghostty before starting the daemon so macOS can ask for Automation permission on first start:

```sh
open -a Ghostty
brew services start thurstonsand/ghosttykit/ghosttykit-nightly
gty doctor
```

You should get an Automation prompt from macOS. Grant access so GhosttyKitD can control Ghostty. Afterward, `gty doctor` should report:

```text
> gty doctor
daemon: ok - socket reachable
automation: ok - Ghostty accepted Apple Events
```

To stop the daemon:

```sh
brew services stop thurstonsand/ghosttykit/ghosttykit-nightly
```

Stable releases will be published as `ghosttykit` once GhosttyKit starts cutting `v*` release tags.

## Development

Project-local tool versions live in `mise.toml`.

```sh
mise install    # install project tools
just build      # build binaries
just check      # format, lint, typecheck, test, build, and validate packaging/CI config
just --list
```

Component recipes are available as `*-go`, `*-swift`, `*-pi`, and `*-nvim` variants.
