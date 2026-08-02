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

## Hidden runtime hooks

These commands are hidden and used by `gty ssh` on the remote host:

```sh
gty ssh remote-init                   # prints remote runtime JSON
GTY_SOCK=/path/to/socket gty ssh remote-run -- command args...
```
