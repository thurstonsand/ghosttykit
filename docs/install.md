# Install

Status: in progress.

The primary macOS install path will be Homebrew. The formula should install:

- `gty`
- `ghosttykitd`
- a `brew services` user service for `ghosttykitd`

Remote hosts normally receive `gty` through `gty ssh` bootstrap. The wrapper first looks for `gty` in remote `PATH`, then `~/.local/bin/gty`. If neither exists or the remote `gty version` line differs from the local one, it installs a fresh `~/.local/bin/gty` over SSH.

When the remote OS/architecture matches the local machine, the wrapper copies the current local executable. From a source checkout, it can also cross-compile a Linux/macOS `amd64` or `arm64` remote binary before copying it. If bootstrap fails, `gty ssh` continues as plain SSH unless `--require-bridge` is set.

Manual remote install target:

```sh
mkdir -p ~/.local/bin
# place a compatible gty binary at ~/.local/bin/gty
chmod 755 ~/.local/bin/gty
```

See [daemon.md](daemon.md) for daemon socket selection and dry-run behavior, and [ssh.md](ssh.md) for bridge behavior.
