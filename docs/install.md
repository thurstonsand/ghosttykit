# Install

Status: stable `v0.4.0` is published.

The primary install path is the shared `thurstonsand/homebrew-tap` Homebrew tap. Stable releases follow `v*` tags:

```sh
brew install thurstonsand/tap/ghosttykit
```

Nightly builds track recent commits on `main` and may break:

```sh
brew install thurstonsand/tap/ghosttykit-nightly
```

On macOS the formula installs:

- `gty`
- `GhosttyKitD.app`, a background-only app bundle containing `ghosttykitd`
- a `brew services` user service for the bundled daemon

On Linux it installs `gty` alone. `ghosttykitd` is macOS-only, so a Linux `gty` is useful as the remote end of a bridge established by `gty ssh` from a macOS host.

After installing from the tap, start the user service while Ghostty is running so macOS can ask for Automation permission on first start:

```sh
open -a Ghostty
brew services start thurstonsand/tap/ghosttykit
gty doctor
```

`gty doctor` proves the socket and service are reachable, then asks the daemon to confirm that it can send Apple Events to Ghostty. See [tcc-macos.md](tcc-macos.md) for macOS Automation behavior.

Remote hosts normally receive `gty` through `gty ssh` bootstrap. The wrapper prefers a `gty` on the remote `PATH` and falls back to its own managed install at `${XDG_DATA_HOME:-$HOME/.local/share}/ghosttykit/bin/gty`, using the first one whose `gty version` line matches the local one. If neither matches, it installs a fresh binary at the managed path over SSH. See [ssh.md](ssh.md#bootstrap) for where that binary comes from. If bootstrap fails, `gty ssh` continues as plain SSH unless `--require-bridge` is set.

A `gty` you install yourself on the remote `PATH` is used as-is while its version matches, and bootstrap never writes over it.

Manual remote install target:

```sh
mkdir -p ~/.local/bin
# place a compatible gty binary at ~/.local/bin/gty
chmod 755 ~/.local/bin/gty
```

Go users can also install `gty` from a tagged release:

```sh
go install github.com/thurstonsand/ghosttykit/cli/gty@vX.Y.Z
```

This installs only the CLI. The binary reports the tag it was installed from, so it bootstraps remote hosts from that release like any other release build. macOS users still need `ghosttykitd`, so Homebrew remains the normal local install path.

## Ghostty config for Neovim navigation

Copy the Ghostty key-table fragment from the root [README](../README.md#ghostty-config-for-neovim-navigation) into your Ghostty config if you use `ghosttykit.nvim` split navigation. GhosttyKit does not modify your config automatically; the required key table name is `nvim`.

## Pi paste extension

Install the stable Pi extension from npm:

```sh
pi install npm:@thurstonsand/pi-paste
```

Use the nightly dist-tag when pairing with `ghosttykit-nightly`:

```sh
pi install npm:@thurstonsand/pi-paste@nightly
```

The extension enables paste over ssh when combined with `gty ssh`.

Optional settings, in `~/.pi/agent/settings.json`:

```json
{
  "paste": {
    "shortcut": "alt+v",
    "outputDir": "/tmp/pi-paste-file"
  }
}
```

See [daemon.md](daemon.md) for daemon socket selection and dry-run behavior, [ssh.md](ssh.md) for bridge behavior, and [tcc-macos.md](tcc-macos.md) for macOS Automation behavior.
