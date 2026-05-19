# Context

## Glossary

- **GhosttyKit**: The standalone Ghostty-adjacent toolkit being extracted from this repository. It includes a macOS daemon for local Ghostty and pasteboard capabilities, a portable client/CLI, editor integrations, and optional remote/SSH forwarding support. Navigation is one capability, not the project boundary.
- **gty**: The primary GhosttyKit command-line interface. Existing `ghostty-nav` naming has no compatibility guarantee and can be removed during migration.
- **ghosttykitd**: The GhosttyKit daemon. The daemon is named after the project/service, not the CLI client.
- **Daemon**: A GhosttyKit Unix-socket endpoint that accepts protocol requests. The main daemon is the long-running `ghosttykitd` endpoint; a bridge daemon is a daemon endpoint owned by `ghosttykitd`, bound to one Ghostty terminal and one SSH session lease.
- **Client**: A `gty` process, SDK caller, or integration that connects to a daemon endpoint and sends protocol requests.
- **Remote bridge**: A per-SSH-session Unix-socket bridge owned by `ghosttykitd`, not a sidecar process. `ghosttykitd` creates a local bridge daemon for the originating Ghostty surface, and `gty ssh` exposes that daemon to the remote host with OpenSSH Unix-socket `RemoteForward`. It must not assume shpool or any other persistent remote shell manager. Multiple bridge sessions from the same local terminal are allowed; each bridge has its own socket and lease. If remote forwarding is unavailable, `gty ssh` should warn and continue as plain SSH.
- **Remote socket cleanup**: Remote sockets should use runtime directories where possible, but Linux `loginctl enable-linger` and non-Linux remotes weaken runtime-directory cleanup assumptions. Cleanup must distinguish active listeners from abandoned socket pathnames.
- **Bridge lease**: The persistent local connection from `gty ssh` to the daemon-owned bridge listener that keeps a remote bridge alive. The lease uses a local-only token so remote request clients cannot pin bridge lifetime. When the lease closes, `ghosttykitd` destroys the local bridge listener and associated state.
- **GTY_SOCK**: The only required remote environment variable for bridge-aware commands. If set, remote `gty` connects to that Unix socket; if absent, commands behave as local commands for the current machine.
- **Public daemon protocol**: The Unix-socket JSON protocol between `gty`, integrations, SDKs, and the macOS daemon is versioned and documented for external integrations.
