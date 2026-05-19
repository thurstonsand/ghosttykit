# SSH Bridge

Status: partial implementation.

`gty ssh` uses OpenSSH Unix-socket reverse forwarding to expose a daemon-owned local bridge socket to a remote `gty` process.

Default behavior is soft failure: if bootstrap, forwarding, or bridge setup fails, `gty ssh` warns and continues as plain SSH. `--require-bridge` makes bridge setup failure fatal for tests and debugging.

## Local bridge lifecycle

GhosttyKit has a daemon-owned local bridge primitive used by the later full SSH wrapper:

1. Local `gty` asks `ghosttykitd` to create a bridge for the current local TTY.
2. `ghosttykitd` resolves that TTY to a trusted Ghostty terminal id.
3. `ghosttykitd` creates a per-session local Unix socket under `~/.local/run/ghosttykit/bridges/`.
4. The daemon returns the local socket path and a local-only lease token.
5. Local `gty` opens a persistent lease connection to that socket and authenticates with the lease token.
6. One-shot request connections to that same socket execute against the bridge-bound terminal id.
7. Closing the lease destroys the bridge session and unlinks the bridge socket.

The lease token is only a lifecycle guard. Remote request connections do not receive it and do not need it.

Hidden debug CLI hooks:

```sh
gty ssh bridge-create                 # prints: SOCKET<TAB>TOKEN
gty ssh bridge-lease SOCKET TOKEN     # holds the lease until interrupted
```

The full SSH wrapper, remote runtime setup, and remote bootstrap flow are not implemented yet.
