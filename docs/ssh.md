# SSH Bridge

`gty ssh` wraps OpenSSH and exposes the originating local Ghostty surface to commands on the remote host.

Default behavior is soft failure. If the bridge cannot be prepared, `gty ssh` prints:

```text
gty: Ghostty bridge unavailable: <reason>
gty: continuing with plain SSH
```

Then it continues as plain SSH. Use `--require-bridge` when the bridge is mandatory:

```sh
gty ssh --require-bridge host
```

## Usage

Simple interactive session:

```sh
gty ssh host
```

A remote command must follow `--`:

```sh
gty ssh host -- gty focus left
```

`gty ssh` does not support ad hoc OpenSSH flags. Put stable connection details such as `Port`, `User`, `ProxyCommand`, or `IdentityFile` in SSH config.

GhosttyKit applies these OpenSSH options internally:

```text
ExitOnForwardFailure=yes
StreamLocalBindUnlink=yes
StreamLocalBindMask=0177
ServerAliveInterval=15
ServerAliveCountMax=3
ControlMaster=no
ControlPath=none
```

For debugging, `--debug-unmanaged-ssh` skips those managed options. `--debug-no-bootstrap` skips the remote `gty` bootstrap attempt.

## Bridge flow

1. `gty ssh` finds or bootstraps a remote `gty`.
2. It runs `gty ssh remote-init` on the remote host.
3. The local daemon creates a daemon-owned bridge socket for the originating Ghostty terminal.
4. `gty ssh` opens a local bridge lease and starts OpenSSH with Unix-socket reverse forwarding:

   ```text
   ssh -R remote_socket:local_bridge_socket host ...
   ```

5. The remote command runs under `gty ssh remote-run` with `GTY_SOCK` set to the forwarded remote socket.
6. Remote `gty` commands connect through `GTY_SOCK` and target the local bridge-bound Ghostty terminal.
7. When the SSH session exits, the remote socket pathname is removed and the local lease closes.

`GTY_SOCK` is the only remote environment variable required by bridge-aware commands.

## Remote runtime cleanup

`gty ssh remote-init` chooses a runtime directory in this order:

```text
$XDG_RUNTIME_DIR/gty
/tmp/gty-$UID
```

It creates the directory with mode `0700`, removes dead GhosttyKit socket pathnames by connect-probing them, preserves active sockets, and prints JSON:

```json
{
  "runtimeDir": "/run/user/501/gty",
  "socketPath": "/run/user/501/gty/bridge-...sock"
}
```

`gty ssh remote-run` parents the remote shell or command, preserves the child exit status, and removes the current `GTY_SOCK` pathname on normal wrapper exit.

## Bootstrap

The remote host needs a `gty` reporting the same `gty version` line as the local one. `gty ssh` uses a `gty` already on the remote `PATH` when its version matches, and otherwise installs its own at `${XDG_DATA_HOME:-$HOME/.local/share}/ghosttykit/bin/gty`. That location stays off `PATH` on purpose: bootstrap should not add a command the host's owner did not install. A `gty` you installed yourself is never overwritten.

Where the installed binary comes from depends on how the local `gty` was built:

- Release builds, including Homebrew and `go install <module>@vX.Y.Z`, download the matching `linux`/`darwin` `amd64`/`arm64` asset from their own GitHub release, reporting progress on stderr. This is the only part of `gty ssh` that reaches the network.
- Source builds (`just build-go`, `just install`) cross-compile from their checkout.
- Anything else, such as a bare `go build`, copies itself to a host matching its own OS and architecture, and reports that it cannot serve any other.

Bootstrap failure is soft: `gty ssh` continues as plain SSH unless `--require-bridge` is set. `--debug-no-bootstrap` skips the install and names the version that did not match.

## Herdr attach

`gty herdr attach` is `gty ssh` with one job: run remote [Herdr](https://herdr.dev) so that `ctrl+h/j/k/l` navigates the innermost layer able to move — a Neovim window, else a Herdr pane, else a Ghostty split.

```sh
gty herdr attach pod042
gty herdr attach pod042 -- --session work
```

| Flag                    | Behavior                                                     |
| ----------------------- | ------------------------------------------------------------ |
| `--key-table <name>`    | Ghostty key table to hold for the session. Default `bypass`. |
| `--herdr-bin <path>`    | The `herdr` executable on the remote host. Default `herdr`.  |
| `--debug-unmanaged-ssh` | Skip GhosttyKit's managed OpenSSH options.                   |
| `--debug-no-bootstrap`  | Skip the remote `gty` bootstrap.                             |

Unlike `gty ssh`, attach fails closed. There is no plain-SSH fallback: bare navigation keys arriving in a remote shell as raw control bytes are worse than a refused attach. Run `ssh host` and `herdr` directly when you do not need integrated navigation.

Attach differs from `gty ssh` in four ways:

- it forces a remote pty even though it runs a remote command;
- it requires `gty` at `${XDG_DATA_HOME:-$HOME/.local/share}/ghosttykit/bin/gty`, whatever else the host has on `PATH`, because Herdr's keybindings name that path ahead of time;
- it filters navigation sentinels out of the SSH output stream;
- it holds the Ghostty key table for the whole session.

The key table is activated only after every preflight succeeds, immediately before OpenSSH starts, and is released on normal exit, SSH failure, and handled `SIGINT`, `SIGTERM`, and `SIGHUP`. `SIGKILL` cannot be handled, so keep a manual key-table reset in your Ghostty config.

### Navigation flow

At a Herdr pane edge, remote `gty herdr navigate` asks Herdr to set the foreground client's window title to `gty-nav:v1:<direction>` and clears it immediately. Local `gty herdr attach` recognizes that exact title in the SSH stream, removes it, and focuses the adjacent Ghostty split for its own terminal. Ghostty never sees the sentinel, and every other byte passes through unchanged.

On a client that is not `gty herdr attach`, such as a phone over plain SSH, the sentinel may briefly appear as the terminal title before Herdr clears it. Herdr's `prefix+h/j/k/l` pane bindings remain the fallback there.

### Herdr configuration

GhosttyKit does not edit `~/.config/herdr/config.toml`. Add these bindings on the remote host before the first attach, then reload Herdr's config:

```toml
[[keys.command]]
key = "ctrl+h"
type = "shell"
command = 'exec "${XDG_DATA_HOME:-$HOME/.local/share}/ghosttykit/bin/gty" herdr navigate left'
description = "navigate left"

[[keys.command]]
key = "ctrl+j"
type = "shell"
command = 'exec "${XDG_DATA_HOME:-$HOME/.local/share}/ghosttykit/bin/gty" herdr navigate down'
description = "navigate down"

[[keys.command]]
key = "ctrl+k"
type = "shell"
command = 'exec "${XDG_DATA_HOME:-$HOME/.local/share}/ghosttykit/bin/gty" herdr navigate up'
description = "navigate up"

[[keys.command]]
key = "ctrl+l"
type = "shell"
command = 'exec "${XDG_DATA_HOME:-$HOME/.local/share}/ghosttykit/bin/gty" herdr navigate right'
description = "navigate right"
```

The absolute path is deliberate: Herdr runs `type = "shell"` commands detached, so they may not inherit an interactive shell's `PATH`, and the host may carry an unrelated `gty` elsewhere. Attach keeps that path at its own version on every connection.

Missing bindings are the unpleasant failure: the key table passes control bytes inward and Herdr hands them to the focused pane instead of running `gty`. Install the config before the first attach.

Also keep the Ghostty `bypass` key table from [`nvim/README.md`](../nvim/README.md#ghostty-key-table); attach reuses it rather than introducing another.

### gty herdr navigate

```text
gty herdr navigate <left|down|up|right>
```

Herdr keybindings are this command's only caller. It resolves its pane from `HERDR_ACTIVE_PANE_ID`, then `HERDR_PANE_ID`, and requires `HERDR_SOCKET_PATH`.

It inspects the pane's foreground processes first and sends the original control key inward when Neovim holds them, letting Neovim move between its own windows. Otherwise it focuses a Herdr neighbor when one exists and signals the outer layer when none does. Any API failure stops the ladder and exits nonzero: moving outward on uncertain state would skip a layer the user expected to navigate. The command prints nothing on success.

A Neovim that received the key runs the remaining two layers itself. `ghosttykit.nvim` speaks the same Herdr socket protocol natively rather than calling back into `gty`, so the hot path carries no process spawn.

## Hidden runtime hooks

These commands are hidden and used by `gty ssh` on the remote host:

```sh
gty ssh remote-init                   # prints remote runtime JSON
GTY_SOCK=/path/to/socket gty ssh remote-run -- command args...
```
