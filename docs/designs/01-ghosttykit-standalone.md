# GhosttyKit Standalone Extraction

## Status

Accepted, migration to occur from ../ansiblonomicon

## Decision Summary

Extract the current `ghostty-nav`, `ghostty-navd`, Neovim integration, SSH bridge behavior, and Pi paste flow into a standalone monorepo named GhosttyKit. The public CLI will be `gty`, the macOS daemon will be `ghosttykitd`, and remote SSH support will use Unix-socket reverse forwarding to daemon-owned per-session bridge listeners. This favors a small, explicit, trusted-user model over compatibility aliases, TCP fallback, or a broad authentication system.

## Problem Statement

The current Ghostty navigation and paste tooling lives inside the `ansiblonomicon` Ansible/dotfiles repository. It now covers more than split navigation: it includes a portable Go client, a macOS Swift daemon, Ghostty AppleScript control, Neovim key-table integration, SSH-forwarded remote behavior, and a Pi Alt-v paste extension that reads local clipboard content through the same daemon.

That scope is large enough to justify a standalone project. The extraction must define product boundaries, package layout, command names, daemon naming, remote SSH identity, cleanup behavior, protocol ownership, and installation strategy before code is moved.

## Goals

- Create a standalone GhosttyKit monorepo for Ghostty-adjacent terminal capabilities.
- Replace `ghostty-nav` naming with `gty` and `ghosttykitd`; no compatibility with the old name is required.
- Keep navigation, layout, key-table, paste, Neovim, SSH bridge, and Pi paste capabilities in the same project.
- Capture the required Ghostty key-table config for `Ctrl-h/j/k/l` navigation and Neovim pass-through.
- Provide a Homebrew-first macOS installation path that installs both `gty` and `ghosttykitd`.
- Support Linux remote hosts through a remote `gty` that the regular SSH connection flow can bootstrap and upgrade where practical.
- Use SSH Unix-socket reverse forwarding for remote control of the originating local Ghostty surface.
- Keep the remote bridge trusted-user and Unix-socket-only; fail softly when forwarding or remote `gty` is unavailable.
- Document the daemon protocol clearly without committing to schema/code generation in v1.

## Non-Goals

- Do not preserve `ghostty-nav` compatibility aliases.
- Do not support TCP fallback transport in v1.
- Do not assume tmux, shpool, systemd user services, or any persistent remote shell/session manager.
- Do not require a separate manual remote host installer for wrapper-mode SSH in v1; bootstrap should be part of the regular connection flow where practical.
- Do not build generated protocol bindings in v1.
- Do not solve arbitrary untrusted-remote authentication. The model is trusted remote user accounts.

## Design Decisions

### 1. Name the project GhosttyKit and the CLI `gty`

The extracted project is **GhosttyKit**. The primary CLI is **`gty`**. The daemon is **`ghosttykitd`**.

`gty` is short enough for frequent terminal use and avoids the clumsiness of `ghosttyctl`. `ghosttykitd` is more idiomatic than `gtyd` or `ghosttyctld` because the daemon belongs to the service/project, not to the control CLI.

There is no old-name compatibility requirement. Existing `ghostty-nav` references can be broken and migrated.

### 2. Treat GhosttyKit as a companion toolkit, not just navigation

GhosttyKit includes navigation, key-table switching, layout commands, clipboard/paste, editor plugins, Pi extensions, and SSH bridge support.

This avoids an awkward split where paste and remote clipboard behavior depend on the same daemon but live in a separate project. Navigation is one capability of the companion toolkit, not the project boundary.

### 3. Use a monorepo with language-specific packages

The project should be a monorepo:

```text
ghosttykit/
  cli/gty/                 # Go CLI, imports sdk/go
  daemon/ghosttykitd/       # Swift macOS daemon
  sdk/go/                   # Go client/protocol package
  sdk/lua/                  # Lua client/protocol package
  nvim/                     # Neovim plugin, consumes sdk/lua
  pi/pi-paste/              # Pi extension npm package
  homebrew/                 # Homebrew tap/formula
  docs/
    protocol.md
    ssh.md
    install.md
```

`cli/gty` is intentionally language-neutral in naming; it should not use `cmd/gty` if the repository may later include more than Go. `pi/pi-paste` should follow Pi package prior art: npm package metadata with a `pi.extensions` entry, similar to Plannotator's package shape.

### 4. Keep protocol documentation hand-written in v1

Do not create a schema/code-generation root in v1. JSON Schema code generation is uneven across Go, Swift, and Lua. Go has usable tools, Swift can use quicktype-style generation, and Lua has validators but weak idiomatic binding generation.

Instead, keep:

- `docs/protocol.md`: wire protocol and command shapes
- manual Go structs in `sdk/go`
- manual Swift `Codable` request handling in `daemon/ghosttykitd`
- manual Lua or TypeScript clients as needed

If schema-first generation becomes valuable later, protobuf is a better candidate than OpenAPI or JSON Schema for multi-language generated bindings.

### 5. Install with Homebrew first

The macOS distribution target is Homebrew. The formula should install both:

- `gty`
- `ghosttykitd`

The formula should expose a `brew services` service using Homebrew's `service do` formula block, with `ghosttykitd` running as a user service.

Both `gty` and `ghosttykitd` should be codesigned where practical. Homebrew source builds may use ad-hoc signing; release artifacts can later use Developer ID signing and notarization.

A packaging proof spike is required because macOS TCC/Automation behavior for launchd-managed AppleScript automation can be unpleasant. If the daemon cannot reliably prompt for or retain permission to control Ghostty, add `gty doctor` or a targeted permission diagnostic flow.

### 6. Bootstrap remote `gty` for SSH bridge mode

Remote SSH bridge mode requires `gty` on the remote host. The regular `gty ssh` connection flow should attempt to bootstrap or upgrade the remote `gty` before bridge setup when practical.

The bootstrap should install a matching `gty` build into a user-owned location such as `~/.local/bin/gty` or a GhosttyKit-managed private directory, then use that binary for `remote-init` and `remote-run`. This avoids requiring Go, PATH setup, outbound network access, or manual remote installation on every host.

If bootstrap cannot run or remote `gty` remains unavailable, `gty ssh` should warn and continue as plain SSH unless `--require-bridge` is set.

Homebrew will cover macOS local installs from day one. Other package managers can come later.

### 7. Use Unix-socket SSH reverse forwarding only

Remote commands should reach the local machine through OpenSSH Unix-socket `RemoteForward`.

No TCP fallback should be implemented in v1. TCP would require token/auth handling, increase exposure, and add a second transport path. If Unix socket forwarding is disabled or unavailable, GhosttyKit controls are unavailable for that SSH session, but the SSH session itself should still continue.

`gty ssh` should fail softly by default:

```text
gty: Ghostty bridge unavailable: <reason>
gty: continuing with plain SSH
```

For debugging, tests, and explicit bridge-dependent workflows, support strict mode:

```sh
gty ssh --require-bridge host
```

In strict mode, missing remote `gty`, failed bootstrap, failed `remote-init`, failed forwarding, or failed bridge `doctor` exits instead of continuing as plain SSH.

`gty ssh` should apply a small set of managed SSH options internally:

```text
ExitOnForwardFailure=yes
StreamLocalBindUnlink=yes
StreamLocalBindMask=0177
ServerAliveInterval=15
ServerAliveCountMax=3
ControlMaster=no
ControlPath=none
```

These are implementation defaults, not primary UI. A debug escape hatch may skip the managed SSH options so a user can supply all SSH behavior manually when diagnosing issues.

The public command grammar should stay minimal:

```sh
gty ssh [gty-options] host
```

If the user needs a remote command, require an explicit delimiter so ownership is clear:

```sh
gty ssh [gty-options] host -- [remote command]
```

The wrapper intentionally does not parse or pass through ad hoc OpenSSH options. Stable connection details belong in SSH config; keeping those out of the command grammar keeps bridge ownership unambiguous.

### 8. Bind remote identity to daemon-owned bridge sessions

Remote processes must not supply trusted terminal identity. The remote endpoint is a bearer capability that routes to a local bridge session owned by `ghosttykitd`.

The identity flow is:

```text
local tty -> ghosttykitd -> Ghostty terminal id -> bridge session -> bridge socket
```

Remote `gty` receives only:

```sh
GTY_SOCK=/path/to/remote/forwarded/socket
```

When `GTY_SOCK` is set, `gty` connects there. When absent, `gty` uses the local daemon socket for the current machine. No `GTY_SESSION`, `GTY_BRIDGE`, local TTY, or terminal id is required in the remote environment.

Every protocol request should include a protocol version field. Local and remote `gty` versions may diverge across bootstrapped remotes and Homebrew-managed local installs, so version mismatch must produce a structured error rather than mysterious command failure.

Remote bridged commands should not use the remote TTY for targeting. The local bridge session already carries the target Ghostty terminal id.

### 9. Use one daemon-owned bridge socket per SSH session

`ghosttykitd` owns both the default daemon socket and per-SSH bridge sockets.

Startup flow:

```text
gty ssh
  -> connects to the default local daemon socket
  -> asks ghosttykitd to create a bridge for the current local TTY

ghosttykitd
  -> resolves local TTY to Ghostty terminal id
  -> creates one local bridge socket for this SSH session
  -> listens on that socket
  -> returns the local bridge socket path

gty ssh
  -> opens a persistent lease connection to that same bridge socket
  -> authenticates the lease with a local-only lease token returned by the daemon
  -> starts ssh -R remote_sock:local_bridge_sock host
```

The same bridge listener handles two connection types:

- **Lease connection:** opened by local `gty ssh` and kept open for the SSH lifetime. The daemon accepts it only when it presents the local-only lease token. When it closes, `ghosttykitd` destroys the bridge session and unlinks the local bridge socket.
- **Request connection:** opened by remote `gty` through `GTY_SOCK` for one command/request/response. Remote requests do not receive or need the lease token.

The lease token is a lifecycle guard, not a broad authentication system. It prevents a remote process from spoofing a lease and pinning a bridge open after the local `gty ssh` wrapper exits.

This avoids a sidecar bridge process and avoids two local sockets per SSH session.

Multiple bridge sessions from the same local terminal are allowed in v1. Random session socket names make them independent, and it is accurate for both to target the same Ghostty terminal id.

### 10. Initialize remote runtime directories before forwarding

OpenSSH creates the remote forward before running the remote command. Therefore the remote directory for a Unix socket must already exist before the main bridged SSH command starts.

For v1, `gty ssh` should always run remote bootstrap/init before the bridged SSH command. Bootstrap is part of the normal connection flow, not a separate required user step:

```text
gty ssh host
  bootstrap or upgrade remote gty if needed
  ssh host 'gty ssh remote-init'
  ssh -R remote_sock:local_bridge_sock host 'GTY_SOCK=... gty ssh remote-run -- ...'
```

`gty ssh remote-init` should:

- choose a runtime directory
- create it with mode `0700`
- clean dead GhosttyKit socket pathnames by connect-probing them
- print the selected runtime directory or socket base path

Runtime directory order:

```text
$XDG_RUNTIME_DIR/gty   if set and writable
/tmp/gty-$UID          fallback, including macOS remotes
```

Linux `loginctl enable-linger` and non-Linux remotes mean runtime directory lifetime must not be treated as the complete cleanup story.

### 11. Clean remote sockets by probing, not metadata or age

Do not add remote socket metadata in v1. It is not required for liveness.

Cleanup should scan only the GhosttyKit-owned runtime directory and test each socket path:

```text
try connect with a short timeout
  success -> listener exists; keep it
  failure -> no listener; unlink it
```

Do not delete sockets because they are old. An active SSH session may sit idle for days, and its socket should remain. Age-based cleanup is valid only for future metadata files if metadata is later added.

Normal exits should remove the current remote socket through `gty ssh remote-run`. Abnormal client sleep, network loss, or `SIGKILL` can leave socket pathnames behind; the next `remote-init` should remove dead ones.

`gty ssh remote-run` should parent the user's remote shell or command, export `GTY_SOCK`, wait for the child, remove the current remote socket on normal exit, and preserve the child exit status. Do not rely on shell traps after `exec`; a parent process is clearer and more reliable.

### 12. Keep commands direct

Keep the existing command style rather than over-namespacing:

```sh
gty doctor
gty terminal-id
gty tab-terminal-count
gty key-table activate nvim
gty key-table deactivate
gty focus left
gty split left
gty resize right --percent 15
gty zoom
gty paste
gty title "..."
gty ssh host
gty ssh remote-init
gty ssh remote-run
```

Future clipboard write support can be a direct verb such as:

```sh
gty copy
```

There is no need for a `clipboard` namespace unless the command surface becomes harder to scan.

### 13. Add a Lua SDK before the Neovim plugin

The Neovim plugin should consume a Lua SDK under `sdk/lua`, not shell out to `gty` for its primary daemon interactions. The Lua SDK should match the Go SDK's behavioral scope while using idiomatic Lua structure:

- protocol version constant and request constructors
- `GTY_SOCK` and default local daemon socket resolution
- one Unix socket connection per request
- JSON request framing and reply decoding
- frame, no-reply, stream, and held-connection reply modes where needed
- protocol error objects with stable response codes
- `doctor` support for health checks

The SDK owns daemon socket transport. The Neovim plugin owns editor behavior: keymaps, `<Plug>` mappings, autocommands, TTY discovery, floating-window navigation decisions, user configuration, and `:checkhealth ghosttykit` presentation.

The first Lua SDK should include both a Neovim runtime transport using `vim.uv` and `vim.json`, and a non-Neovim runtime transport using LuaRocks dependencies such as `luv` and a JSON library. The public SDK API should hide the transport choice so Neovim and other Lua consumers use the same request-level contract.

### 14. Ship the Ghostty key-table config as part of the integration

The `Ctrl-h/j/k/l` behavior is not only a Neovim plugin concern. Ghostty owns those keys in the default key table and switches a terminal surface into an `nvim` key table while Neovim is active. That config is a required integration artifact for the standalone extraction.

Source config:

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

Standalone docs should include this as a copyable Ghostty config fragment. Installation should not silently overwrite a user's Ghostty config; it should document the fragment and, if automation is later added, install it only by explicit user action.

The important invariant is that `gty key-table activate nvim` and `gty key-table deactivate` target a key table named `nvim`. Renaming the table would require coordinated changes in the Ghostty config, Neovim plugin, and daemon command behavior.

### 15. Package Pi paste as a real Pi package

The Pi Alt-v paste flow belongs in the monorepo under `pi/pi-paste`. It should be packaged like a Pi extension npm package, not copied from local dotfiles.

The package should depend on `gty paste --json --output-dir ...` and support the same local/remote endpoint behavior as the CLI: if `GTY_SOCK` is set, it uses the forwarded bridge; otherwise it uses the local daemon.

## Edge Cases & Failure Modes

- **Remote `gty` missing or bootstrap fails:** `gty ssh` warns and continues as plain SSH unless `--require-bridge` is set. Ghostty controls are unavailable in that session.
- **Remote forwarding disabled:** `gty ssh` warns and continues as plain SSH unless `--require-bridge` is set.
- **Remote runtime directory missing:** `gty ssh remote-init` creates it before the bridged SSH command starts.
- **Remote socket path remains after abnormal disconnect:** next `gty ssh remote-init` connect-probes and removes dead socket pathnames.
- **Active SSH session idle for a long time:** socket cleanup preserves it because the listener remains connectable.
- **Laptop sleeps with active bridge:** local processes freeze; remote commands should use short timeouts and fail softly. On wake, the SSH connection may resume or die. If it dies, local `gty ssh` exits, the lease closes, and `ghosttykitd` removes local bridge resources.
- **Server reboot:** remote listeners disappear. Runtime directories under `/run/user` are normally gone. Local SSH exits eventually, closing the local bridge lease.
- **Client reboot:** local daemon and bridge sockets disappear. Remote `sshd` eventually notices the dead connection; stale remote Unix socket pathnames may remain until remote init cleanup.
- **Ghostty terminal mapping bootstrap on current Ghostty AppleScript:** first local TTY-to-terminal-id discovery may require the originating terminal to be focused when Ghostty does not expose terminal TTYs. The daemon should detect AppleScript capabilities at runtime and use direct TTY lookup when available.
- **Multiple Ghostty panes SSH to the same host:** each `gty ssh` session receives a different random endpoint routed to its own local bridge session.
- **Multiple SSH sessions from the same local terminal:** allowed in v1; each bridge is independent but targets the same Ghostty terminal id.
- **Neovim navigation bridge unavailable:** fail silently or with debug-only logging. Do not block editor navigation.
- **Paste bridge unavailable:** report a user-visible error; paste is an explicit action.

## Rejected Alternatives

### Preserve `ghostty-nav` compatibility

Rejected because this is an extraction and rename, not a compatibility release. Keeping aliases would add migration complexity and undercut the broader GhosttyKit naming.

### Split navigation and paste into separate projects

Rejected because both capabilities rely on the same daemon, socket transport, remote forwarding, and local macOS authority. Splitting them would create an artificial boundary.

### TCP fallback for remote bridge

Rejected because it requires token/auth handling, adds exposure, and creates a second transport behavior. Unix-socket forwarding is the supported v1 path. If it is unavailable, controls are unavailable.

### Global forwarded daemon socket

Rejected because identity would have to be supplied by the remote caller. That breaks the core invariant: remote code must not be trusted to choose the local Ghostty terminal surface.

### Sidecar bridge process per SSH session

Rejected because `ghosttykitd` can own per-session bridge listeners directly. A sidecar adds process lifecycle and cleanup complexity without a clear benefit.

### Separate lease socket and request socket

Rejected because one bridge listener can handle both persistent lease connections and one-shot request connections.

### Metadata-driven remote cleanup

Rejected for v1 because metadata is not needed to determine socket liveness. Connect-probing the socket path is more direct and avoids lying age-based cleanup.

### Unauthenticated lease messages

Rejected because the bridge listener is reachable through the forwarded remote socket. A local-only lease token is a small lifecycle guard that prevents remote request clients from pinning a bridge open.

### JSON Schema or OpenAPI as protocol source of truth

Rejected for v1. JSON Schema code generation is uneven across target languages, especially Lua. OpenAPI is the wrong abstraction for Unix-socket RPC. Hand-written protocol docs and language implementations are simpler.

### CLI-backed Neovim plugin as the primary implementation

Rejected. Shelling out to `gty` is useful as a fallback or debugging path, but the standalone project already has an SDK boundary. The Neovim plugin should exercise the same daemon protocol through `sdk/lua` that other Lua consumers will use.

## Integration Points

- `ansiblonomicon:ansible/roles/ghostty_nav/files/ghostty-nav`: source for the initial `cli/gty` Go package and Go SDK split.
- `ansiblonomicon:ansible/roles/ghostty_nav/files/ghostty-navd`: source for `daemon/ghosttykitd`.
- `ansiblonomicon:chezmoi/dot_config/nvim/lua/lib/ghostty-nav.lua`: source for the standalone Neovim plugin.
- `ansiblonomicon:chezmoi/dot_config/nvim/lua/plugins/ghostty-navigator.lua`: source for plugin registration and key mappings.
- `ansiblonomicon:chezmoi/dot_config/ghostty/config.tmpl`: source for the Ghostty `Ctrl-h/j/k/l` default bindings and `nvim` key table.
- `ansiblonomicon:chezmoi/private_dot_pi/agent/extensions/pi-paste-file`: source material for `pi/pi-paste`, but packaging should follow Pi package conventions rather than local extension conventions.
- `ansiblonomicon:docs/designs/11-ghostty-nav-daemon.md`: historical daemon/client design to supersede during extraction.
- `ansiblonomicon:docs/designs/12-ghostty-ssh-nvim-bridge.md`: historical SSH bridge design; its remote identity assumptions should not be revived except as context.
- `ansiblonomicon:docs/designs/13-pi-paste-file.md`: source context for paste behavior and Pi extension requirements.
- Homebrew formula: installs `gty`, `ghosttykitd`, and a user service for `ghosttykitd`.
- Remote bootstrap flow: installs or upgrades a remote `gty` binary before `remote-init` when practical.

## Implementation Plan

- [x] Phase 1: Create standalone repository skeleton
  - Goal: Establish the GhosttyKit monorepo without changing the current in-repo deployment yet.
  - Files: new external `ghosttykit/` repository or staging directory; `README.md`, `docs/`, `cli/gty/`, `daemon/ghosttykitd/`, `sdk/go/`, `nvim/`, `pi/pi-paste/`, `homebrew/`.
  - Work:
    - Initialize the repository layout.
    - Add root README with project scope, trust model, and current status.
    - Add development tooling for Go, Swift, TypeScript/Pi package, and Lua formatting where applicable.
    - Add `docs/protocol.md`, `docs/ssh.md`, `docs/install.md`, and `docs/tcc-macos.md` as initial documentation stubs.
  - Validation:
    - Repository builds no artifacts yet but lint/tool commands exist or clearly no-op.
    - Documentation names match GhosttyKit / `gty` / `ghosttykitd` consistently.

- [x] Phase 2: Extract and rename the Go CLI and Go SDK
  - Goal: Move the current Go `ghostty-nav` client into `cli/gty` and split reusable client/protocol code into `sdk/go`.
  - Files: `ansible/roles/ghostty_nav/files/ghostty-nav/**` -> `cli/gty/**`, `sdk/go/**`.
  - Work:
    - Rename module/package paths from `ghostty-nav` to GhosttyKit paths.
    - Rename binary from `ghostty-nav` to `gty`.
    - Move daemon socket selection, request framing, TTY discovery, OSC title, paste materialization, and Unix socket client code into reusable Go SDK packages where useful.
    - Rename commands: `move` -> `focus`, `activate/deactivate` -> `key-table activate/deactivate`, `toggle-zoom` -> `zoom`.
    - Add protocol version fields to all requests and structured error handling.
    - Define the hard-break GhosttyKit protocol used by the CLI and Go SDK; the Swift daemon must adopt this protocol in Phase 3.
  - Validation:
    - `go test ./...` passes in `sdk/go` and `cli/gty`.
    - `gty doctor`, `gty paste --json`, and layout commands work locally after `ghosttykitd` adopts the GhosttyKit protocol.

- [x] Phase 3: Extract and rename the Swift daemon
  - Goal: Move the Swift daemon into `daemon/ghosttykitd` and rename service/socket/log paths.
  - Files: `ansible/roles/ghostty_nav/files/ghostty-navd/**` -> `daemon/ghosttykitd/**`.
  - Work:
    - Rename binary to `ghosttykitd`.
    - Rename runtime paths to GhosttyKit/gty paths.
    - Update request decoding to accept the versioned `gty` protocol and renamed commands.
    - Keep local Ghostty AppleScript control and pasteboard behavior intact.
    - Add startup cleanup for daemon-owned local sockets.
    - Add runtime AppleScript capability detection for direct TTY lookup when Ghostty exposes it; keep focused-terminal bootstrap fallback.
  - Validation:
    - Swift format/lint/build passes.
    - `gty doctor`, key-table, focus, split, resize, zoom, title, and paste work locally.
    - Daemon restart removes stale local daemon/bridge sockets.

- [x] Phase 4: Implement daemon-owned SSH bridge sessions
  - Goal: Add local bridge sessions to `ghosttykitd` and local bridge creation to `gty ssh`.
  - Files: `daemon/ghosttykitd/**`, `sdk/go/**`, `cli/gty/**`, `docs/protocol.md`, `docs/ssh.md`.
  - Work:
    - Add daemon request to create a bridge for the current local TTY.
    - Daemon resolves TTY to Ghostty terminal id and creates one short local bridge socket.
    - Daemon returns local bridge socket path and local-only lease token.
    - Bridge listener accepts authenticated lease connections and one-shot request connections.
    - Lease closure destroys bridge state and unlinks the local bridge socket.
    - Remote request connections execute against the bridge-bound terminal id and ignore any remote TTY for targeting.
  - Validation:
    - Unit tests cover lease token acceptance/rejection and bridge cleanup on lease close.
    - Manual local simulated bridge request reaches the correct Ghostty terminal.
    - Remote request cannot spoof a lease without the local-only token.

- [x] Phase 5: Implement `gty ssh` wrapper, bootstrap, `remote-init`, and `remote-run`
  - Goal: Provide the first end-to-end SSH bridge flow.
  - Files: `cli/gty/**`, `sdk/go/**`, `docs/ssh.md`, `docs/install.md`.
  - Work:
    - Add `gty ssh [gty-options] host` and `gty ssh [gty-options] host -- [remote command]`; defer ad hoc OpenSSH option passthrough.
    - Add `--require-bridge` strict mode.
    - Apply managed SSH options internally: `ExitOnForwardFailure=yes`, `StreamLocalBindUnlink=yes`, `StreamLocalBindMask=0177`, `ServerAliveInterval=15`, `ServerAliveCountMax=3`, `ControlMaster=no`, `ControlPath=none`.
    - Add debug escape hatch to skip managed SSH options.
    - Implement transparent remote `gty` bootstrap/upgrade where practical.
    - Implement `gty ssh remote-init`: choose runtime dir, validate/create it, connect-probe and remove dead owned socket pathnames, print JSON result.
    - Implement `gty ssh remote-run`: export `GTY_SOCK`, parent shell/command, remove current remote socket on normal exit, preserve child exit status.
    - Soft mode warns and continues plain SSH on bridge setup failure; strict mode exits.
  - Validation:
    - `gty ssh host` works as plain SSH when remote `gty` is absent or forwarding is disabled.
    - `gty ssh --require-bridge host` fails clearly in those cases.
    - Remote `gty focus left` reaches local Ghostty through `GTY_SOCK`.
    - Stale dead remote socket pathnames are removed by `remote-init`; active sockets are preserved.

- [x] Phase 6: Package macOS Homebrew install
  - Goal: Install `gty` and `ghosttykitd` through Homebrew with a user service.
  - Files: `homebrew/`, `daemon/ghosttykitd/`, `cli/gty/`, `docs/install.md`, `docs/tcc-macos.md`.
  - Work:
    - Add a conventional `thurstonsand/homebrew-ghosttykit` tap that installs `gty` and the app-bundled daemon.
    - Add `service do` block for `ghosttykitd` with `brew services` support.
    - Codesign and notarize release archives.
    - Add `gty doctor` diagnostics for daemon reachability and macOS Automation/TCC permission failures.
    - Package `ghosttykitd` inside `GhosttyKitD.app` so TCC records the stable bundle identity instead of versioned Cellar executable paths.
  - Validation:
    - `brew install thurstonsand/ghosttykit/ghosttykit-nightly` works on macOS.
    - `brew services start thurstonsand/ghosttykit/ghosttykit-nightly` starts `ghosttykitd`.
    - Daemon can send a harmless AppleEvent to Ghostty after permission is granted.
    - Permission failure produces actionable diagnostics.

- [ ] Phase 7-1: Add Lua SDK and Lua tooling
  - Goal: Create a real Lua SDK before extracting the Neovim plugin, matching the Go SDK's daemon protocol scope without copying its Go package structure.
  - Files: `sdk/lua/**`, `mise.toml`, root `justfile`, `docs/protocol.md` if protocol documentation needs Lua notes.
  - Work:
    - Add `ghosttykit` Lua package under `sdk/lua` with LuaRocks metadata.
    - Add protocol constants, request constructors, reply-mode handling, response-code errors, `GTY_SOCK`/default socket resolution, and `doctor` support.
    - Add Unix socket transports for Neovim (`vim.uv`/`vim.json`) and non-Neovim Lua (`luv` plus a LuaRocks JSON dependency), hidden behind one SDK API.
    - Add StyLua, luacheck, LuaCATS annotations, LuaLS-compatible project config, and busted tests as part of the component setup.
    - Add just recipes for `fmt`, `lint`, `typecheck`, `test`, and `check`, and wire them into root commands.
    - Keep SDK code free of Neovim editor behavior such as keymaps, autocommands, window navigation, and health UI.
  - Validation:
    - Lua SDK tests cover request encoding, socket path selection, frame/no-reply/stream/hold behavior where implemented, and response-code error mapping.
    - A test Unix socket can receive a `doctor` request and return a decoded `doctor` reply through both supported transports where the runtime is available.
    - Root `just fmt`, `just lint`, `just typecheck`, and `just test` include the Lua SDK.

- [ ] Phase 7: Extract Neovim plugin
  - Goal: Publish the current Neovim navigation integration as a standalone plugin using `sdk/lua`.
  - Files: `chezmoi/dot_config/nvim/lua/lib/ghostty-nav.lua`, `chezmoi/dot_config/nvim/lua/plugins/ghostty-navigator.lua` -> `nvim/**`; consume `sdk/lua`.
  - Work:
    - Rename plugin/module to GhosttyKit naming.
    - Port current navigation and floating-window behavior.
    - Use `ghosttykit` SDK requests for key-table activate/deactivate and focus movement.
    - Add `ghosttykit.nvim` module, `<Plug>` mappings, opt-in `default_keymaps`, user configuration validation, basic vimdoc, and `:checkhealth ghosttykit` backed by the SDK `doctor` request.
    - Keep any CLI-backed path as fallback or debugging behavior only, not as the primary implementation.
  - Validation:
    - Local Ghostty + Neovim split navigation works.
    - Remote Neovim over `gty ssh` routes edge navigation to the originating local Ghostty pane.
    - Bridge failures do not block editor navigation.
    - `:checkhealth ghosttykit` reports daemon `doctor` checks and actionable bridge/Ghostty context.

- [ ] Phase 8: Document Ghostty key-table config
  - Goal: Make the Ghostty-side `Ctrl-h/j/k/l` bindings a first-class part of the Neovim navigation integration.
  - Files: `chezmoi/dot_config/ghostty/config.tmpl` -> `docs/install.md` or `docs/ghostty.md`.
  - Work:
    - Add a copyable Ghostty config fragment for default `Ctrl-h/j/k/l` split navigation.
    - Add the `nvim` key table that passes `Ctrl-h/j/k/l` through as raw control bytes while Neovim is active.
    - Document that the table name must remain `nvim` unless the Neovim plugin and daemon commands are changed together.
    - Do not include unrelated personal Ghostty keybinds in the public GhosttyKit fragment.
    - Avoid silently modifying user Ghostty config; make any automated install explicit.
  - Validation:
    - Shell `Ctrl-h/j/k/l` moves between Ghostty splits.
    - Neovim `Ctrl-h/j/k/l` moves inside Neovim or falls through to `gty focus` at edges.
    - The documented fragment contains only GhosttyKit-relevant keybinds.

- [ ] Phase 9: Package Pi paste extension
  - Goal: Move Alt-v paste behavior into a real Pi extension package.
  - Files: `chezmoi/private_dot_pi/agent/extensions/pi-paste-file/**` -> `pi/pi-paste/**`.
  - Work:
    - Create npm package metadata with `pi.extensions` entry, modeled on Pi package conventions.
    - Rename package to a GhosttyKit name such as `@ghosttykit/pi-paste`.
    - Call `gty paste --json --output-dir ...` and respect local/remote endpoint behavior through `GTY_SOCK`.
    - Make the `gty` path configurable if needed.
    - Document that the extension can read the local macOS clipboard through GhosttyKit when used over a bridge.
  - Validation:
    - `pi install` from local package works.
    - Alt-v pastes text directly and materializes file/image clipboard content.
    - Remote Pi session over `gty ssh` can paste through the forwarded bridge.
    - Missing bridge or missing `gty` produces a clear user-visible error.

- [ ] Phase 10: Migrate this repository to consume GhosttyKit
  - Goal: Replace embedded role/dotfile sources with installation/consumption of the standalone project.
  - Files: `ansible/roles/ghostty_nav/**`, macOS playbooks/tags, chezmoi Ghostty/Nvim/Pi references, docs/designs cross-references.
  - Work:
    - Remove or deprecate embedded `ghostty_nav` source after standalone package is validated.
    - Update Ansible to install GhosttyKit from Homebrew or local checkout during development.
    - Update Ghostty config and helper scripts to call `gty` and new command names.
    - Preserve the Ghostty `nvim` key table and `Ctrl-h/j/k/l` default split bindings in the migrated config.
    - Update Neovim plugin config to use the standalone plugin.
    - Update Pi extension install/config to use the standalone package.
    - Mark older design docs superseded where appropriate.
  - Validation:
    - `uv run poe laptop --tags ghostty-nav` or replacement tag installs the new package path.
    - Existing `ghostty-ide`, `ideo`, Neovim navigation, SSH bridge, and Pi paste workflows still work.
    - `uv run poe lint` passes.

- [ ] Phase 11: Public release readiness
  - Goal: Make the extracted project reviewable and installable by other users.
  - Files: `README.md`, `docs/**`, release workflow files, package metadata.
  - Work:
    - Add install docs for Homebrew, remote bootstrap, Neovim plugin, and Pi extension.
    - Add troubleshooting docs for SSH forwarding, `GTY_SOCK`, remote bootstrap, stale sockets, and macOS TCC.
    - Add minimum manual test matrix covering two Ghostty panes to the same host, forwarding disabled, daemon restart, stale remote socket cleanup, and paste over bridge.
    - Add release automation for Go binaries, Swift daemon, Homebrew formula updates, and Pi package publishing as appropriate.
    - Evaluate replacing generated AppleScript source strings with direct AppleEvents for safer argument passing and lower control overhead.
  - Validation:
    - Fresh-machine install path succeeds from documentation.
    - End-to-end local and remote workflows pass the documented test matrix.
