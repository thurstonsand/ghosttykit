# GhosttyKit

GhosttyKit is a Ghostty companion toolkit for macOS-local terminal control, editor navigation, SSH-bridged commands, and clipboard paste workflows.

What's available:

- `ghosttykitd`: the macOS daemon required for Ghostty control commands.
- `gty`: a CLI for Ghostty terminal control, SSH bridging, and paste workflows.
- `ghosttykit.nvim`: a Neovim plugin for moving between Neovim windows and Ghostty splits.
- `pi-paste`: a Pi extension for pasting local clipboard text and files, including from SSH sessions opened with `gty ssh`.
- SDKs for building integrations:
  - Go: `sdk/go/`
  - TypeScript: `sdk/ts/`
  - Lua: `sdk/lua/`

Status: stable. The Go `gty` CLI, Swift daemon, Go/TypeScript/Lua SDKs, SSH bridge flow, Homebrew packaging, Neovim plugin, Pi paste extension, and release workflow are present.

## Install

GhosttyKit is distributed through the shared `thurstonsand/homebrew-tap` Homebrew tap. macOS gets `gty` and the daemon; Linux gets `gty` alone, for use as the remote end of a `gty ssh` bridge.

Stable releases follow `v*` tags:

```sh
brew install thurstonsand/tap/ghosttykit
```

Nightly builds track recent commits on `main`:

```sh
brew install thurstonsand/tap/ghosttykit-nightly
```

Start Ghostty before starting the daemon so macOS can ask for Automation permission on first start:

```sh
open -a Ghostty
brew services start thurstonsand/tap/ghosttykit
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
brew services stop thurstonsand/tap/ghosttykit
```

## Ghostty config for Neovim navigation

Add this fragment to your Ghostty config to make `Ctrl-h/j/k/l` move between Ghostty splits in shells, while passing those keys through to Neovim when `ghosttykit.nvim` activates the `nvim` key table:

```ghostty
# ctrl-hjkl navigates Ghostty splits unless this surface is in the nvim key table
keybind = ctrl+h=goto_split:left
keybind = ctrl+j=goto_split:down
keybind = ctrl+k=goto_split:up
keybind = ctrl+l=goto_split:right
keybind = nvim/
keybind = nvim/ctrl+h=text:\x08
keybind = nvim/ctrl+j=text:\x0a
keybind = nvim/ctrl+k=text:\x0b
keybind = nvim/ctrl+l=text:\x0c
```

The key table must be named `nvim`. That name is shared by the Ghostty config and the Neovim plugin. GhosttyKit does not edit your Ghostty config automatically.

## Development

Project-local tool versions live in `mise.toml`.

```sh
mise install    # install project tools
just build      # build binaries
just check      # format, lint, typecheck, test, build, and validate packaging/CI config
just --list
```

Component recipes are available as `*-go`, `*-swift`, `*-ts`, `*-pi`, and `*-nvim` variants.
