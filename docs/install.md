# Install

Status: stable `v0.3.0` is published.

The primary macOS install path is the `thurstonsand/homebrew-ghosttykit` Homebrew tap. Stable releases follow `v*` tags:

```sh
brew install thurstonsand/ghosttykit/ghosttykit
```

Nightly builds track recent commits on `main` and may break:

```sh
brew install thurstonsand/ghosttykit/ghosttykit-nightly
```

The formula installs:

- `gty`
- `GhosttyKitD.app`, a background-only app bundle containing `ghosttykitd`
- a `brew services` user service for the bundled daemon

After installing from the tap, start the user service while Ghostty is running so macOS can ask for Automation permission on first start:

```sh
open -a Ghostty
brew services start thurstonsand/ghosttykit/ghosttykit
gty doctor
```

`gty doctor` proves the socket and service are reachable, then asks the daemon to confirm that it can send Apple Events to Ghostty. See [tcc-macos.md](tcc-macos.md) for macOS Automation behavior.

Remote hosts normally receive `gty` through `gty ssh` bootstrap. The wrapper first looks for `gty` in remote `PATH`, then `~/.local/bin/gty`. If neither exists or the remote `gty version` line differs from the local one, it installs a fresh `~/.local/bin/gty` over SSH.

When the remote OS/architecture matches the local machine, the wrapper copies the current local executable. From a source checkout, it can also cross-compile a Linux/macOS `amd64` or `arm64` remote binary before copying it. If bootstrap fails, `gty ssh` continues as plain SSH unless `--require-bridge` is set.

Manual remote install target:

```sh
mkdir -p ~/.local/bin
# place a compatible gty binary at ~/.local/bin/gty
chmod 755 ~/.local/bin/gty
```

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
