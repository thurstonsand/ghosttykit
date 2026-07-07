# Context

- GhosttyKit: The standalone Ghostty-adjacent toolkit. It encompasses the core of this project: an extension of Ghostty, taking the form of a macOS daemon for Ghostty and pasteboard capabilities, SDKs in a variety of languages for interacting with the daemon, and a portable client/CLI `gty` for a command line interface.
- ghosttykitd: The GhosttyKit daemon. It owns Ghostty control interactions, along with associated helpers such as file paste support.
- Daemon: A GhosttyKit Unix-socket endpoint that accepts protocol requests. The main daemon is the long-running `ghosttykitd` endpoint; a bridge daemon is a daemon endpoint owned by `ghosttykitd`, bound to one Ghostty terminal and one SSH session lease for remote communications.
- Remote bridge: A per-SSH-session Unix-socket bridge owned by `ghosttykitd`. `ghosttykitd` creates a local bridge daemon for the originating Ghostty surface, and `gty ssh` exposes that daemon to the remote host with OpenSSH Unix-socket `RemoteForward`.
- Bridge lease: The persistent local connection from `gty ssh` to the daemon-owned bridge listener that keeps a remote bridge alive. The lease uses a local-only lease token so remote request clients cannot pin bridge lifetime. When the lease closes, `ghosttykitd` destroys the local bridge listener and associated state.
- Lease token: The local-only credential that authorizes holding a bridge lease. Never travels to remote hosts.
- Spawn token: A single-use credential `ghosttykitd` mints whenever it creates a new terminal (e.g. `gty split`) that is used to bind a new terminal's TTY to the terminal id that the daemon created.
- `gty`: The primary GhosttyKit command-line interface client.
- Client: A `gty` process, SDK caller, or integration that connects to a daemon endpoint and sends protocol requests.
- Remote agent: An ephemeral process owned by `gty ssh remote-run` on the remote host that holds a bridge connection open for local-to-remote operations during one bridged SSH session.
- You: the coding agent helping me build `ghosttykit`.
- Me/Us: the developer(s) building `ghosttykit`.
- Coding agent: tools like Amp, Pi, Claude Code, Codex, or similar processes running in terminal contexts.
- Integration: a plugin, extension, script, project using the SDK. Many are built into this repo (e.g. nvim, pi), but they can be implemented anywhere.
