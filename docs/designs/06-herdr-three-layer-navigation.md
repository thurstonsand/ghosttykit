# Three-layer directional navigation owned by `gty`

## Status

Accepted

This revises the earlier “Three-layer directional navigation: Ghostty → Herdr → Neovim” draft. It keeps the innermost-first decision ladder and the Herdr foreground-client title channel, but changes ownership:

- no upstream Herdr change;
- no standalone `herdr-nav` executable;
- no remote `gty nav-wrap` PTY wrapper;
- one `gty herdr` command group owns attach orchestration and Herdr navigation;
- the title sentinel is consumed by the local SSH process, before it reaches Ghostty.

The intended repository location is `docs/designs/06-herdr-three-layer-navigation.md` in GhosttyKit.

### Implementation amendments

The body below records the design as decided. Implementation changed four things; the rest landed as written.

- **The Ghostty key table is named `bypass`, not `nvim`.** Two different inner layers activate it, so it is named for what it does to Ghostty's own bindings rather than for one tenant.
- **`ghosttykit.nvim` speaks Herdr's socket directly, and `--from-nvim` does not exist.** Alternative 4 below rejects a Lua Herdr client to keep policy in one place. That reasoning held for the full ladder but not for its tail: the plugin already speaks the GhosttyKit daemon protocol natively, and a flag whose only meaning is "start at step 2" is a subprocess spawn on the hottest path to communicate a constant. The plugin now runs neighbor → focus, or the sentinel at an edge, over `HERDR_SOCKET_PATH`. `gty herdr navigate` keeps the full ladder for Herdr's own keybindings, which need a subprocess regardless. The sentinel spelling now lives in Go and Lua, each commented as the other's counterpart.
- **`SessionOptions` carries a fourth field, `ForwardSignals`.** Signal handling has to own the `exec.Cmd`, and keeping it in the transport leaves `gty ssh` untouched while attach's cleanup still runs after OpenSSH exits.
- **Attach does not preflight remote Herdr method availability.** That needs a running remote server and another round trip; it belongs to the deferred `gty herdr doctor`. Caller TTY, bridge, managed `gty`, and remote `herdr` presence are all checked.

Phase 3 ships as documentation rather than installed configuration. Phase 5 hardening remains open, including the two-client stress test for the accepted foreground-client race.

## Decision summary

Bare `ctrl+h/j/k/l` navigates the innermost layer able to move:

1. a Neovim window;
2. otherwise a Herdr pane;
3. otherwise a Ghostty split.

Ghostty passes those keys inward while a Herdr attach is active. Herdr invokes a remote `gty herdr navigate <direction>` command. That command either forwards the key into Neovim, focuses a neighboring Herdr pane, or asks the foreground Herdr client to set a versioned sentinel title.

The local `gty herdr attach` process filters the SSH output stream. When it sees the exact sentinel OSC, it removes the sequence and asks GhosttyKit to focus the adjacent Ghostty split for the attach’s original local TTY. The sentinel never reaches Ghostty, so the integrated path does not visibly or semantically replace the Ghostty tab title.

`ghosttykit.nvim` uses the same remote command at a Neovim edge:

```text
gty herdr navigate --from-nvim <direction>
```

There is no separate navigation script and no Herdr protocol implementation in Lua.

The remaining compromise is Herdr’s foreground-client race. A key event normally promotes its source client before the binding runs, and the title API targets that foreground client. Herdr runs `type = "shell"` commands detached, however, so another attached client can become foreground before `gty herdr navigate` emits the sentinel. Centralizing the work in one Go process minimizes that interval but cannot eliminate it without client identity from Herdr or an input-side terminal proxy.

## Clarification: the existing GhosttyKit “OSC dance”

Two existing GhosttyKit mechanisms are easy to conflate.

### New terminal startup uses a spawn token

Race-free initialization of daemon-created Ghostty terminals is described in [`04-spawn-token-terminal-binding.md`](https://github.com/thurstonsand/ghosttykit/blob/main/docs/designs/04-spawn-token-terminal-binding.md). `ghosttykitd` already knows the new terminal id from the split reply. It wraps the new terminal’s command so its first action is a one-shot `gty spawn-claim <token>`, binding the new PTY to that terminal before the real command starts.

That mechanism does not use OSC.

### Organic terminal identification uses a temporary OSC 7 working directory

[`05-osc7-rendezvous-tty-resolution.md`](https://github.com/thurstonsand/ghosttykit/blob/main/docs/designs/05-osc7-rendezvous-tty-resolution.md) handles terminals the daemon did not create. The daemon writes a temporary OSC 7 working-directory nonce to the caller’s TTY, scans Ghostty’s scripting tree for the terminal reporting that nonce, then restores the real working directory.

That is the mechanism remembered as “temporarily changing something without leaving it changed.” It uses the reported working directory, not the title. That design explicitly rejected OSC 0/2 titles because Ghostty coalesces title changes, title overrides can discard them, and title changes are visible.

### Relationship to this design

The Herdr sentinel uses the same broad pattern: temporarily place a recognizable value on a channel that crosses an otherwise missing identity boundary, consume it at the process that has the missing identity, then restore normal state.

It is not the same protocol:

| Existing OSC 7 rendezvous                                                     | Herdr navigation sentinel                                                                    |
| ----------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| Identifies which Ghostty terminal owns a local PTY                            | Carries an outward navigation result to the correct attached client                          |
| Ghostty must apply the property so `ghosttykitd` can observe it               | Ghostty must not see the sentinel                                                            |
| Uses OSC 7 because Ghostty applies it immediately and exposes it to scripting | Uses a title because Herdr exposes `client.window_title.set/clear` for the foreground client |
| Restores the real working directory after matching                            | Filters the sentinel locally, then lets Herdr’s normal title clear pass through              |

Using a title is acceptable here for the reason it was unacceptable in the OSC 7 resolver: Ghostty is not the observer. `gty herdr attach` sees the raw bytes from SSH before Ghostty’s title parser, strips the sentinel, and performs the focus action directly. Ghostty’s title debounce and title override behavior are irrelevant.

On a client not using `gty herdr attach`, such as a phone over plain SSH, the sentinel can briefly appear as the outer terminal title before Herdr clears it. That is degradation, not the integrated behavior.

## Problem statement

Three nested layers want the same keys:

1. Ghostty has native splits.
2. Herdr has panes inside a remote persistent session.
3. Neovim has windows inside a Herdr pane.

Input arrives outermost-first:

```text
Ghostty → SSH/Herdr → Neovim
```

The navigation decision must be made innermost-first:

```text
Neovim window? → Herdr pane? → Ghostty split?
```

If Ghostty consumes a key merely because it has a split in that direction, Neovim and Herdr never receive it. If Herdr consumes every key, Neovim cannot navigate its own windows. At Herdr’s outer edge, server-side code does not know which local Ghostty surface originated the key, especially when two Herdr clients are attached.

The earlier draft solved the last hop with a remote PTY wrapper and a separate `herdr-nav` script. Both are avoidable:

- local `gty ssh` already knows the originating Ghostty TTY;
- OpenSSH already owns PTY allocation, raw input, resize forwarding, and signal handling;
- `gty` can speak Herdr’s documented socket API itself;
- the local SSH stdout path is the earliest point where the sentinel can be removed before Ghostty sees it.

## Constraints

- Ghostty splits remain.
- Herdr remains and runs remotely.
- Neovim runs inside Herdr panes.
- `ctrl+h/j/k/l` remains the only navigation chord family.
- LazyVim continues to own the Neovim mappings through `ghosttykit.nvim`.
- No upstream Herdr work is required for the implementation.
- Multiple Herdr clients must remain usable. Strictly race-free per-client outer navigation is not claimed without an upstream identity primitive.

## Goals

- Preserve innermost-first navigation across all three layers.
- Add no standalone helper executable or shell script.
- Keep Herdr-specific policy under a coherent `gty herdr` command group.
- Reuse the current Ghostty `nvim` key table rather than introduce another key-table migration.
- Keep the title sentinel out of Ghostty on integrated attaches.
- Keep local non-Herdr Neovim behavior unchanged.
- Fail without leaving the Ghostty key table active whenever cleanup is possible.
- Make the remaining multi-client race narrow, measurable, and explicit.

## Non-goals

- Independent per-client focus inside Herdr. Herdr’s attached clients share the server’s focused pane.
- Cooperative navigation for arbitrary TUIs. Neovim is the only inner application recognized in the initial implementation.
- Automatic editing of `~/.config/herdr/config.toml`.
- Replacing `gty ssh` as the generic remote transport.
- Building a general terminal proxy.
- Hiding every title effect on clients that do not use the integrated attach command.

## User-facing shape

### Attach

```sh
gty herdr attach pod042
```

Optional Herdr arguments follow `--`:

```sh
gty herdr attach pod042 -- --session work
```

A short user-owned alias remains reasonable:

```sh
alias hdr='gty herdr attach pod042'
```

The command:

1. verifies local GhosttyKit access for the caller TTY;
2. installs the current `gty` at the stable managed path on the remote host;
3. prepares the existing GhosttyKit SSH bridge;
4. activates the configured Ghostty key table for the caller TTY;
5. starts `herdr` under a forced remote PTY;
6. filters navigation sentinels from SSH stdout;
7. deactivates the key table and resets terminal modes when the session ends.

The bridge remains available to other remote `gty` calls, although the navigation path itself uses the local attach process for the Ghostty hop.

The default key table is `nvim`, matching the current plugin and Ghostty configuration. The name is historical; its actual meaning is “pass directional navigation keys to an inner navigator.”

Proposed flags:

```text
gty herdr attach [flags] host [-- herdr arguments]

  --key-table <name>          default: nvim
  --herdr-bin <path>          default: herdr
  --debug-unmanaged-ssh
  --debug-no-bootstrap
```

Unlike generic `gty ssh`, `gty herdr attach` fails closed when the Ghostty bridge or local daemon is unavailable. Silently falling back to plain SSH while leaving the user expecting integrated bare-key navigation is worse than a clear failure. Plain fallback is already available explicitly:

```sh
ssh pod042
herdr
```

### Navigate

```text
gty herdr navigate [--from-nvim] <left|down|up|right>
```

This is integration plumbing, but it remains a documented command because both Herdr configuration and `ghosttykit.nvim` call it.

Default behavior assumes invocation from a Herdr keybinding:

```text
inspect focused pane
    foreground process is nvim → send ctrl+direction into that pane
    otherwise neighbor exists   → focus neighbor
    otherwise                   → emit outer-navigation sentinel
```

`--from-nvim` means Neovim has already tried and failed to move internally:

```text
skip process inspection and key forwarding
    neighbor exists → focus neighbor
    otherwise       → emit outer-navigation sentinel
```

Direction encoding is fixed:

| Direction | Key sent to Neovim |
| --------- | ------------------ |
| left      | `ctrl+h`           |
| down      | `ctrl+j`           |
| up        | `ctrl+k`           |
| right     | `ctrl+l`           |

The command prints nothing on success.

## Herdr configuration

Herdr custom commands receive `HERDR_SOCKET_PATH` and `HERDR_ACTIVE_PANE_ID`, and `type = "shell"` runs detached. The keybindings invoke the managed `gty` binary directly:

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

Herdr’s existing `prefix+h/j/k/l` pane bindings remain. They are the bridge-free fallback and do not participate in the bare-key ladder.

The absolute managed path avoids three problems:

- detached custom commands may not receive an interactive shell’s `PATH`;
- the remote host may have another `gty` version on `PATH`;
- the current bootstrap code can select a compatible `PATH` binary without populating the managed path.

`gty herdr attach` therefore needs a managed-bootstrap mode that always ensures this exact path contains the attaching client’s version, even when another compatible `gty` exists elsewhere.

It should not change generic `gty ssh` selection behavior.

## Architecture

```text
┌─────────────────────────────────────────────────────────────────────┐
│ Local Ghostty surface                                                │
│                                                                     │
│  nvim key table: ctrl+h/j/k/l → raw control bytes                  │
│             │                                                       │
│             ▼                                                       │
│  gty herdr attach                                                   │
│    ├─ owns original local TTY                                       │
│    ├─ owns key-table lifecycle                                      │
│    ├─ runs OpenSSH with remote PTY                                  │
│    └─ filters SSH stdout                                            │
│             │                                                       │
└─────────────┼───────────────────────────────────────────────────────┘
              │ SSH
              ▼
┌─────────────────────────────────────────────────────────────────────┐
│ Remote Herdr client/server                                           │
│                                                                     │
│  Herdr bare-key binding                                              │
│       │                                                             │
│       ▼                                                             │
│  managed gty herdr navigate <dir>                                   │
│       ├─ pane.process_info                                          │
│       ├─ pane.send_keys, or                                         │
│       ├─ pane.neighbor + pane.focus_direction, or                   │
│       └─ client.window_title.set/clear sentinel                     │
│                                                                     │
│  Neovim edge                                                        │
│       └─ gty herdr navigate --from-nvim <dir>                       │
└─────────────────────────────────────────────────────────────────────┘
              │ foreground client display stream
              ▼
┌─────────────────────────────────────────────────────────────────────┐
│ Local stdout filter                                                  │
│                                                                     │
│  ordinary bytes / ordinary OSC → Ghostty unchanged                  │
│  gty-nav sentinel            → drop + local SDK focus(original TTY) │
└─────────────────────────────────────────────────────────────────────┘
```

## Detailed navigation flow

### Shell or another non-Neovim process

1. `gty herdr attach` has activated the `nvim` Ghostty key table for this surface.
2. Ghostty turns `ctrl+h` into raw byte `0x08` and sends it to SSH.
3. Herdr recognizes its bare `ctrl+h` custom binding and starts:

   ```sh
   gty herdr navigate left
   ```

4. `gty` reads `HERDR_ACTIVE_PANE_ID`.
5. It calls `pane.process_info`.
6. If the foreground process is not Neovim, it calls `pane.neighbor` for `left`.
7. If a neighbor exists, it calls `pane.focus_direction`.
8. If no neighbor exists, it emits the title sentinel and immediately clears it.

A process-inspection or neighbor-query error is not treated as an edge. The command does nothing and exits nonzero. A dead key is safer than skipping a layer on uncertain state.

### Neovim can move internally

1. Herdr’s bare-key binding starts `gty herdr navigate left`.
2. `pane.process_info` identifies `nvim` in the foreground process group.
3. `gty` calls `pane.send_keys` with `ctrl+h`.
4. `ghosttykit.nvim` receives its existing normal-mode mapping.
5. Neovim moves to its left window.

Insert-mode and terminal-mode behavior remains Neovim’s behavior because Herdr sends the original key into the pane rather than interpreting it as a Neovim navigation request.

### Neovim is at its edge

1. `ghosttykit.nvim` determines that its current window cannot move left.
2. Because `HERDR_ENV=1`, it does not call GhosttyKit’s local `focus` API.
3. It starts asynchronously:

   ```sh
   gty herdr navigate --from-nvim left
   ```

4. The command resolves its pane from `HERDR_PANE_ID`.
5. It skips `pane.process_info` and `pane.send_keys`, preventing a loop.
6. It focuses a left Herdr neighbor, or emits the outer sentinel if none exists.

### Herdr is at its edge

1. Remote `gty` sends:

   ```json
   {
     "method": "client.window_title.set",
     "params": { "title": "gty-nav:v1:left" }
   }
   ```

2. Herdr targets the current foreground attached client.
3. The Herdr client serializes the title update into its terminal display stream.
4. The local `gty herdr attach` filter sees the complete OSC.
5. It does not write that OSC to stdout.
6. It calls GhosttyKit’s focus operation with:

   ```text
   TTY: the original local TTY captured by gty herdr attach
   Direction: left
   ```

7. Remote `gty` sends `client.window_title.clear` immediately after the set request.
8. Herdr’s normal title restoration passes through the filter.

No remote `GTY_SOCK` is needed for this hop. The process acting on Ghostty is already local and already has the exact TTY.

## `gty herdr navigate` implementation

### Context resolution

The command accepts these contexts:

| Invocation                                    | Pane variable          |
| --------------------------------------------- | ---------------------- |
| Herdr `[[keys.command]]`                      | `HERDR_ACTIVE_PANE_ID` |
| Process inside a Herdr pane, including Neovim | `HERDR_PANE_ID`        |

Resolution order:

1. explicit internal test option, if present;
2. `HERDR_ACTIVE_PANE_ID`;
3. `HERDR_PANE_ID`;
4. error: not in a usable Herdr context.

`HERDR_SOCKET_PATH` is required. `HERDR_ENV=1` is checked for the Neovim path but is not the sole authority, because custom commands use the active-pane variables supplied by Herdr.

### Herdr API adapter

Add a small Go client under `cli/gty/internal/herdr`.

It uses Herdr’s documented newline-delimited JSON socket protocol and implements only:

- `pane.process_info`;
- `pane.neighbor`;
- `pane.focus_direction`;
- `pane.send_keys`;
- `client.window_title.set`;
- `client.window_title.clear`;
- `ping`, for tests and a future doctor command.

The adapter should use typed request and response structs for the fields the decision ladder needs, while ignoring unknown fields. Herdr documents protocol-version checking and forward-compatible handling of unknown fields.

The final implementation should talk to the socket directly rather than spawning the `herdr` CLI for every request. A CLI-backed prototype is acceptable, but three CLI process starts per keypress add latency and widen the foreground-client interval for no architectural benefit.

Herdr’s socket server may close ordinary request connections after one response. The adapter should not assume a persistent multi-request connection; it can open short local connections per method. The relevant improvement is avoiding external process startup, not forcing one socket lifetime.

### Foreground-process detection

Initial allowlist:

```text
nvim
```

Compare process basenames, not full paths. If Herdr reports several foreground-process entries, any `nvim` entry is enough to defer the key inward.

Do not infer Neovim from pane title text, command-line fragments from unrelated processes, or agent metadata.

A later option may make the allowlist configurable. It is not required for the first implementation.

### Failure policy

The command only moves outward on affirmative evidence:

- `pane.process_info` must succeed before deciding a pane is not Neovim;
- `pane.neighbor` must succeed and explicitly report no neighbor before emitting a sentinel.

Errors produce no navigation action. Detached keybinding errors should be available through Herdr’s normal command logging or GhosttyKit debug logging, but should not print into the pane’s PTY.

## Sentinel protocol

### Payload

```text
gty-nav:v1:<left|down|up|right>
```

The version is part of the exact match. Unknown versions pass through unchanged.

### Accepted framing

The streaming filter accepts either title selector and either standard terminator:

```text
ESC ] 0 ; gty-nav:v1:left BEL
ESC ] 2 ; gty-nav:v1:left BEL
ESC ] 0 ; gty-nav:v1:left ESC \
ESC ] 2 ; gty-nav:v1:left ESC \
```

The observed Herdr framing may use only one of these forms. Accepting the standard variants makes the filter tolerant of client-side encoding changes without broadening the payload contract.

### Parser requirements

The parser is stateful across arbitrary read boundaries. It must:

- preserve every nonmatching byte exactly;
- recognize OSC sequences split at every possible byte;
- accept BEL and ST terminators;
- cap buffered OSC length, for example at 256 bytes;
- flush oversized, malformed, or unterminated sequences unchanged;
- match only the exact sentinel payload and known direction;
- serialize focus callbacks;
- flush a partial buffered sequence unchanged at EOF.

A regular expression per `Write` call is incorrect because terminal sequences can be split across reads.

### Title behavior

The sentinel set sequence is removed before Ghostty sees it. Therefore Ghostty’s title does not become `gty-nav:v1:left` during an integrated attach.

The clear request still matters:

- a plain, unfiltered client needs it;
- Herdr’s client may maintain title override state;
- the normal default-title OSC is harmless when the sentinel was filtered.

Set and clear are consecutive. There is no sleep. The earlier draft’s 100 ms delay would increase visible title time on plain clients and widen the multi-client race.

### Collision and trust

Any process with access to the Herdr API can deliberately set the exact sentinel title. Under an integrated attach, that can move a Ghostty split.

This is a limited focus capability, not arbitrary local command execution. The remote host is already trusted to provide the interactive terminal stream. The parser still restricts the action to four enum values and never interprets payload text as a command.

## `gty herdr attach` implementation

### Reuse `gty ssh` internals, not its public policy

The current SSH runner already:

- bootstraps a matching remote `gty`;
- creates a bridge bound to the caller’s local TTY;
- owns the final OpenSSH process;
- resets interactive terminal modes for PTY sessions.

It needs three reusable capabilities:

1. force PTY allocation even when a remote command is present;
2. inject an stdout writer or transform;
3. require the stable managed remote `gty` path.

These should be internal runner options. The public `gty ssh` command does not need a Herdr-specific flag.

A possible internal shape:

```go
type SessionOptions struct {
    ForcePTY         bool
    Stdout           io.Writer
    RequireManagedGTY bool
}
```

The exact type is implementation detail. The important separation is that `gty herdr attach` supplies policy while `internal/remote` supplies transport.

### Why the filter is local

The previous `gty nav-wrap` design put the wrapper on the remote host around the Herdr client. That wrapper would need to:

- allocate and manage a nested PTY;
- copy stdin and stdout;
- forward `SIGWINCH`;
- mirror terminal dimensions;
- forward signals;
- unwind terminal modes;
- rely on remote `GTY_SOCK`;
- clean up the Ghostty key table through the bridge.

None of that is needed locally. OpenSSH already owns the remote PTY and terminal transport. The local parent can filter the SSH child’s stdout while leaving the child’s stdin attached directly to the real TTY, preserving OpenSSH’s terminal handling.

### Key-table lifecycle

The attach command owns the key table for the whole Herdr session:

```text
all preparation succeeds
    activate key table on original TTY
    run SSH
finally
    deactivate key table on original TTY
    reset terminal modes
    close bridge lease
```

Activation occurs immediately before launching the final SSH process, not while bootstrap and preflight work runs.

Cleanup runs on:

- normal Herdr detach or exit;
- SSH failure;
- handled `SIGINT`, `SIGTERM`, and `SIGHUP`;
- command startup failure.

`SIGKILL` and process crashes cannot run cleanup. The existing manual Ghostty key-table escape remains necessary as a last resort.

### Managed remote binary

Current GhosttyKit bootstrap prefers a compatible `gty` on remote `PATH` and installs the managed binary only when needed. Herdr configuration cannot safely refer to whichever path happened to win during a prior attach.

Add an internal “ensure managed” operation:

```text
${XDG_DATA_HOME:-$HOME/.local/share}/ghosttykit/bin/gty
```

`gty herdr attach` always ensures that path reports the exact local `gty` version. The install remains staged and atomically renamed, as in the current bootstrap.

Generic `gty ssh` keeps its current preference order.

### Preflight and fallback

Before key-table activation, attach should verify:

- caller TTY resolves through GhosttyKit;
- the configured key table can be activated;
- remote managed `gty` is runnable;
- remote `herdr` binary is present;
- the remote Herdr socket protocol supports the required methods when a server is already running.

The command cannot reliably prove that the four user-managed TOML bindings are active without taking ownership of Herdr configuration. Missing bindings remain a setup error documented by `gty herdr doctor` or installation docs.

Default behavior is fail closed. There is no automatic plain-SSH fallback.

## `ghosttykit.nvim` changes

### Environment detection

Add:

```lua
function M.in_herdr()
  return vim.env.HERDR_ENV == "1"
end
```

Processes inside Herdr panes receive `HERDR_ENV=1` and `HERDR_PANE_ID`.

### Navigation backend

The current edge path calls `client.focus(direction)` directly. Replace that call with a mux dispatcher:

```text
inside Herdr → asynchronously run gty herdr navigate --from-nvim <direction>
otherwise    → current GhosttyKit focus call
```

Internal Neovim window movement is unchanged.

The remote executable resolution order should be:

1. explicit plugin option, if configured;
2. GhosttyKit managed path under `XDG_DATA_HOME` or `~/.local/share`;
3. `gty` found on `PATH`;
4. report a quiet navigation failure.

This keeps existing local installations untouched while making the Herdr path deterministic after `gty herdr attach` has bootstrapped the remote binary.

### Key-table ownership

The current plugin activates the Ghostty key table on `VimEnter`, `VimResume`, and `FocusGained`, then deactivates it on `VimSuspend` and `VimLeavePre`.

Inside Herdr, those autocmds must not own key-table state. The outer attach needs bare navigation keys even when focus moves from Neovim to a shell pane. If Neovim deactivated the table when it exited or suspended, Herdr would stop receiving the keys.

Rule:

```lua
if not env.in_herdr() then
  setup_key_table_autocmds()
end
```

The plugin still installs its `<Plug>` mappings under Herdr. Only the Ghostty key-table lifecycle is skipped.

### LazyVim

No LazyVim-specific branch is needed.

The current bundled lazy.nvim spec continues to map `ctrl+h/j/k/l` to the existing `<Plug>` mappings. The change is below that layer: the plugin’s edge backend selects Herdr instead of Ghostty, and attach owns key-table state.

## Multiple attached clients

### Normal path

Herdr promotes a client to foreground when it receives interactive input from that client, then routes the input. Its title API sends `WindowTitle` to the foreground client. In ordinary use:

```text
client A sends ctrl+h
Herdr promotes A
Herdr dispatches A's custom binding
gty emits sentinel
Herdr sends title to A
A's local attach focuses A's Ghostty surface
```

Focus-gained events also promote clients, so clicking or focusing a Ghostty surface normally establishes the expected client before the navigation key.

### Remaining race

`type = "shell"` commands run detached. This sequence is possible:

```text
A sends ctrl+h
Herdr promotes A and starts detached gty
B sends input
Herdr promotes B
A's gty process reaches client.window_title.set
Herdr sends sentinel to B
```

If B is another integrated Ghostty attach, B’s outer Ghostty surface can move. If B is a plain client, it may see a title flash.

Set and clear are separate API requests and each targets the then-current foreground client. A foreground change between them can also send the clear to a different client.

No rearrangement inside GhosttyKit can make this formally race-free because the public Herdr command context does not include the triggering client id.

### Mitigation

- one `gty` process owns the complete decision;
- direct socket calls avoid `herdr` subprocess startup;
- set and clear are consecutive;
- no sleep;
- the outer signal is emitted only after a definitive no-neighbor result;
- two-client stress tests gate release.

If realistic stress testing produces wrong-surface moves at an acceptable typing cadence, this design should not paper over them with longer delays. The next viable mechanism is an input-side local proxy with correlation, described in Alternatives.

Herdr’s shared-focus model already means two clients issuing pane navigation at the same time contend over one server focus. This design does not change that behavior.

## Failure modes

### Bridge or local daemon unavailable

`gty herdr attach` fails before activating the key table. The error tells the user to run plain SSH/Herdr if integrated navigation is not needed.

### Remote bootstrap fails

Attach fails before local state changes. The stable managed path is never replaced with a partial binary because installation uses a staged sibling and atomic rename.

### Herdr binary missing

Attach fails before key-table activation.

### Herdr bindings missing or stale

The key table passes raw control bytes inward, but Herdr may pass them to the focused pane instead of invoking `gty`. This is the most unpleasant deployment failure. Documentation must put config installation before first attach, and a future `gty herdr doctor` should inspect as much active state as Herdr exposes.

The manual Ghostty key-table reset remains the immediate escape hatch.

### Herdr API request fails

Navigation stops at the current layer. It does not assume “no neighbor” on an error and does not jump to Ghostty.

### Neovim process detection fails

The key is not forwarded and Herdr does not move. A dead key is preferable to unexpectedly leaving Neovim.

### Neovim-side `gty` is unavailable

Internal Neovim movement still works. At a Neovim edge, the plugin reports or logs a quiet failure and does not skip directly to Ghostty.

### SSH dies while a full-screen app owns terminal modes

Attach performs the same terminal reset currently used by `gty ssh` PTY sessions, then deactivates the key table.

### Attach process is killed without cleanup

The key table can remain active. `SIGKILL` cannot be handled. Keep the existing manual deactivation binding documented.

### Plain SSH or phone client

Bare Herdr pane navigation and Neovim forwarding still work if the server bindings are active. At the Herdr edge there is no Ghostty action; the sentinel may briefly appear as a title and clear. Prefix navigation remains available.

### Sentinel collision

A deliberate exact title can cause one of four Ghostty focus operations under an integrated attach. Nonmatching titles pass through byte-for-byte.

### Herdr foreground behavior changes

If a Herdr update stops promoting the key source before binding dispatch, outer navigation may route to the wrong client. Pin the behavior in an integration test against supported Herdr versions and include it in `gty herdr doctor` diagnostics where possible.

## Alternatives

### 1. Keep a separate `herdr-nav` script

Status: rejected for the final design.

It can implement the decision ladder with Herdr CLI calls and is a reasonable throwaway prototype. It adds another executable, another deployment path, shell quoting, and several process starts per key. `gty` already needs Herdr awareness for Neovim and attach behavior, so splitting the core decision into a shell script creates two owners without reducing complexity.

### 2. Keep the remote `gty nav-wrap` PTY wrapper

Status: rejected.

It can consume the same sentinel and use bridged `GTY_SOCK`. It also reimplements terminal transport around Herdr even though OpenSSH already owns it. Resize, signals, PTY modes, stream copying, and cleanup all become GhosttyKit’s problem. The local SSH parent already knows the correct TTY and can filter the same bytes earlier.

### 3. Add `--navigation=herdr` to generic `gty ssh`

Status: technically viable, rejected as the primary public surface.

The transport changes belong in `internal/remote`, but Herdr-specific process detection, config, sentinel semantics, and key-table policy do not belong in the generic SSH command. `gty herdr attach` gives the behavior an honest name and can fail closed without changing `gty ssh`’s soft-fallback contract.

### 4. Have `gty herdr navigate` shell out to the Herdr CLI

Status: acceptable prototype, rejected for the final path.

Herdr documents CLI wrappers for automation, and this avoids writing response structs initially. A typical key can require process inspection, neighbor lookup, and an action, producing several process starts. That latency is unnecessary and lengthens the foreground-client race. A small documented socket adapter is a better permanent dependency.

### 5. Implement the Herdr socket protocol directly in Lua

Status: rejected.

It avoids spawning `gty` from Neovim, but duplicates request framing, response parsing, direction logic, and error policy in Lua and Go. Lua still cannot own the local SSH output filter. One remote `gty` command keeps the policy in one place.

### 6. Use `herdr-splits.nvim`

Status: rejected as the owner, useful as prior art.

It can cover Neovim-to-Herdr movement, but not the Herdr-to-Ghostty handoff. Running it alongside `ghosttykit.nvim` creates two mapping and edge-navigation owners. Its behavior can inform tests without becoming another runtime dependency.

### 7. Package the navigation as a Herdr plugin

Status: deferred, not needed for the mechanism.

A plugin can distribute keybindings and invoke an executable. It does not expose the triggering client id, so it does not solve the hard race. For one user-managed setup, four config entries and the bootstrapped `gty` are simpler. A plugin may become useful later as an installation layer.

### 8. Use `herdr --remote`

Status: rejected as the primary attach.

A local Herdr thin client is attractive because the display client is already local. By default it uses local keybindings, but local custom command bindings are not sent because they would execute on the remote host. `--remote-keybindings server` restores the remote commands by switching the whole attach to server keybindings. The same remote `gty` and title handoff are still required, while the user loses normal local-keybinding behavior.

### 9. Reuse the OSC 7 TTY rendezvous

Status: rejected.

OSC 7 solves local PTY-to-Ghostty-terminal identity by making Ghostty expose a temporary working directory to AppleScript. Herdr does not offer an equivalent foreground-client working-directory API. OSC 7 emitted inside a pane concerns pane metadata, not the outer attached client. The title API is the documented per-foreground-client display channel.

### 10. Emit a custom OSC or DCS directly from the remote command

Status: rejected.

Bytes printed by a server-side process do not inherently identify which attached Herdr client should receive them. Herdr’s `client.window_title.set` supplies the routing behavior. A private raw escape sequence loses that property.

### 11. Call `gty focus` server-side through `GTY_SOCK`

Status: rejected.

A long-lived Herdr server’s environment belongs to whichever process started it. It cannot represent two current attaches. A cached or inherited `GTY_SOCK` can target the wrong Ghostty surface after reattach and is undefined with multiple clients.

### 12. Use an input-side local proxy with request correlation

Status: deferred as the strict-correctness fallback.

A local proxy could observe that a particular attached client sent `ctrl+h`, remember a short-lived direction token, and honor only a matching sentinel on that client’s output. A misrouted sentinel would then be ignored instead of moving another Ghostty surface.

To preserve OpenSSH behavior, the proxy would need to own a PTY or equivalent terminal plumbing: raw mode, signal forwarding, resize forwarding, bracketed paste, keyboard protocol details, and EOF handling. That is substantially more code and risk than an output filter. Build it only if multi-client stress tests show the foreground race is real in normal use.

### 13. Maintain a downstream Herdr patch or fork

Status: rejected.

Exposing the triggering client id or adding a client-side command type would solve the identity problem cleanly. The maintenance cost is the premise for this redesign, so the implementation cannot depend on it.

### 14. Use a separate chord family

Status: rejected.

It avoids routing entirely by making the user choose the layer. That violates the one-chord, no-mode requirement.

### 15. Use Ghostty `performable:goto_split`

Status: rejected.

It gives the outer layer first refusal. Ghostty consumes the key whenever it can move, even when Neovim or Herdr also could. That is the inverse of the required ordering.

### 16. Mirror inner edge state into Ghostty key tables

Status: rejected.

Per-direction edge state yields sixteen combinations before accounting for focus and two inner layers. Every layout or focus update would race a remote state mirror. It replaces an explicit handoff with stale distributed state.

### 17. Let the sentinel reach Ghostty and clear it later

Status: rejected.

It works mechanically but produces title flashes and depends on Ghostty title timing. The local attach process already has an interception point, so allowing the sentinel through is needless.

### 18. Encode the signal with zero-width title characters

Status: rejected.

Unicode normalization, font behavior, sanitization, terminal title limits, and copy/debug tooling make “invisible title text” a fragile protocol. Exact byte filtering is simpler and testable.

## Implementation plan

### Phase 1: Herdr client and navigation command

Goal: one remote `gty` command owns the complete Neovim-or-Herdr-or-outer decision.

Files:

```text
cli/gty/commands_herdr.go
cli/gty/internal/herdr/client.go
cli/gty/internal/herdr/navigation.go
cli/gty/internal/herdr/*_test.go
cli/gty/main.go
docs/cli.md
```

Work:

- add the `gty herdr` Cobra command group;
- add `gty herdr navigate`;
- implement context and direction validation;
- implement the documented Herdr socket calls;
- implement `nvim` foreground detection;
- implement immediate title set/clear at an outer edge;
- add fake-client decision-table tests.

Validation:

- shell pane with a neighbor moves in Herdr;
- Neovim pane receives the original control key;
- outer edge emits and clears `gty-nav:v1:<direction>`;
- API errors do not move outward.

At this phase the sentinel can visibly flash because no local filter exists yet.

### Phase 2: Local attach and sentinel filter

Goal: `gty herdr attach` owns the local session and turns outer sentinels into Ghostty focus without changing the title.

Files:

```text
cli/gty/commands_herdr.go
cli/gty/internal/osc/filter.go
cli/gty/internal/osc/filter_test.go
cli/gty/internal/remote/args.go
cli/gty/internal/remote/wrapper.go
cli/gty/internal/remote/bootstrap.go
cli/gty/internal/remote/*_test.go
docs/ssh.md
docs/cli.md
```

Work:

- add forced PTY support for a remote command;
- add injectable stdout to the SSH runner;
- add managed-path bootstrap mode;
- add attach key-table lifecycle;
- add the streaming OSC filter;
- route recognized directions through the local Go SDK using the original TTY;
- make attach fail closed;
- reset terminal modes and deactivate the table on every handled exit path.

Validation:

- a manually printed sentinel is stripped and moves only the originating Ghostty surface;
- ordinary OSC titles and arbitrary output remain byte-identical;
- the filter passes tests with every possible read split;
- attach exit restores normal Ghostty key behavior;
- two simultaneous attaches use distinct local TTY targets.

### Phase 3: Herdr keybindings and deployment

Goal: remove the standalone helper from the deployment plan.

Files outside GhosttyKit:

```text
Herdr config.toml
Ghostty config, only if the existing nvim key table is absent
shell alias or wrapper, optional
```

Work:

- add the four `[[keys.command]]` entries using the managed `gty` path;
- retain prefix pane bindings;
- document config reload;
- replace the old `hdr` command body with `gty herdr attach pod042`, or use a shell alias.

Validation:

- shell pane navigation crosses Herdr and Ghostty edges;
- plain SSH retains prefix fallback;
- missing managed `gty` is repaired by the next integrated attach.

### Phase 4: `ghosttykit.nvim` Herdr backend

Goal: complete the three-layer ladder without adding Lua protocol code.

Files:

```text
nvim/lua/ghosttykit/nvim/env.lua
nvim/lua/ghosttykit/nvim/navigation.lua
nvim/lua/ghosttykit/nvim/nvim.lua
nvim/lua/ghosttykit/nvim/herdr.lua
nvim/lua/ghosttykit/nvim/config.lua
nvim/tests/*
nvim/README.md
```

Work:

- detect `HERDR_ENV=1`;
- resolve the managed remote `gty`;
- start `gty herdr navigate --from-nvim` asynchronously at a Neovim edge;
- skip Ghostty key-table autocmd ownership inside Herdr;
- retain current local Ghostty behavior;
- extend health output with Herdr context and executable resolution.

Validation:

- Neovim windows move internally;
- a Neovim edge moves to a Herdr pane;
- a combined Neovim and Herdr edge moves to Ghostty;
- local Neovim outside Herdr behaves exactly as before;
- leaving Neovim for a Herdr shell does not deactivate the attach key table.

### Phase 5: hardening and release gate

Goal: decide whether the accepted foreground-client race is tolerable in practice.

Work:

- scripted two-client alternating-input test;
- rapid opposing-direction test;
- focus-gained then navigation test;
- SSH disconnect and signal cleanup tests;
- plain-client title behavior test;
- supported Herdr-version check;
- documentation of the accepted race and manual reset.

Release gate:

- no sentinel reaches Ghostty under an integrated attach;
- no wrong-surface move appears in deterministic alternating-client tests;
- realistic manual stress does not produce wrong-surface movement;
- if wrong-surface movement is reproducible at normal input cadence, stop and revisit the input-side proxy alternative.

## Test matrix

| Context                                        | Expected result                                                |
| ---------------------------------------------- | -------------------------------------------------------------- |
| Local shell in Ghostty                         | Ghostty split movement, unchanged                              |
| Local Neovim with internal window              | Neovim movement, unchanged                                     |
| Local Neovim at edge                           | Ghostty movement, unchanged                                    |
| Herdr shell with pane neighbor                 | Herdr pane movement                                            |
| Herdr shell at pane edge                       | Ghostty movement                                               |
| Neovim in Herdr with internal window           | Neovim movement                                                |
| Neovim in Herdr at window edge, Herdr neighbor | Herdr pane movement                                            |
| Neovim and Herdr both at edge                  | Ghostty movement                                               |
| Ghostty also at edge                           | no-op                                                          |
| Plain SSH client at Herdr edge                 | no outer movement; title set/clear may be visible              |
| Two integrated clients, alternating keys       | each outer move targets its own Ghostty surface                |
| Herdr API unavailable                          | no outward skip                                                |
| Attach bootstrap failure                       | no active Ghostty key table                                    |
| SSH killed                                     | terminal reset and key-table deactivation where signals permit |

## Observability

A future `gty herdr doctor` is useful but not required for the first implementation.

It should report:

```text
local caller TTY
GhosttyKit daemon reachability
configured key table
remote managed gty path and version
remote Herdr binary and version
Herdr socket path and protocol ping
required method availability
HERDR_ENV / pane-id context when run inside a pane
foreground-process classification for the current pane
```

It should not mutate Herdr config. Config installation remains declarative in the user’s dotfiles.

Debug logs should distinguish:

- process classified as Neovim;
- Herdr neighbor found;
- Herdr edge confirmed;
- sentinel set result and clear result;
- local sentinel intercepted;
- local Ghostty focus result.

Normal navigation remains silent.

## Security considerations

- The remote host controls the SSH display stream already. The new capability is limited to requesting one of four local Ghostty focus directions.
- The filter accepts an exact versioned payload and does not evaluate text.
- The managed remote command uses an absolute path.
- Remote bootstrap preserves the existing atomic-install behavior.
- No local daemon socket path or Ghostty terminal id is placed in the sentinel.
- The existing reverse bridge remains a bearer capability scoped to the attach’s terminal. This design does not expand its target-selection rules.

## Final decision

Implement:

```text
gty herdr attach
gty herdr navigate
```

Keep the title sentinel, but consume it locally before Ghostty sees it. Move the navigation ladder into `gty`, not a new `herdr-nav` executable. Reuse the current Ghostty key table and the existing SSH/bootstrap machinery. Make `ghosttykit.nvim` call the same remote command at its edge and stop managing key-table state while inside Herdr.

Do not implement the upstream Herdr change, remote PTY wrapper, generic SSH navigation mode, or separate navigation script.

The design is operationally small. Its one unresolved correctness limit is explicit: Herdr’s detached custom command can lose foreground-client identity to a competing client interaction. Test that aggressively. If it proves material, the next move is an input-correlating local proxy, not another title delay or another shell wrapper.

## References

GhosttyKit:

- [Spawn Token Terminal Binding](https://github.com/thurstonsand/ghosttykit/blob/main/docs/designs/04-spawn-token-terminal-binding.md)
- [OSC 7 Rendezvous TTY Resolution](https://github.com/thurstonsand/ghosttykit/blob/main/docs/designs/05-osc7-rendezvous-tty-resolution.md)
- [`gty ssh` command](https://github.com/thurstonsand/ghosttykit/blob/main/cli/gty/commands_ssh.go)
- [SSH runner](https://github.com/thurstonsand/ghosttykit/blob/main/cli/gty/internal/remote/wrapper.go)
- [Remote bootstrap](https://github.com/thurstonsand/ghosttykit/blob/main/cli/gty/internal/remote/bootstrap.go)
- [`ghosttykit.nvim` navigation](https://github.com/thurstonsand/ghosttykit/blob/main/nvim/lua/ghosttykit/nvim/navigation.lua)
- [`ghosttykit.nvim` lifecycle](https://github.com/thurstonsand/ghosttykit/blob/main/nvim/lua/ghosttykit/nvim.lua)

Herdr:

- [Custom command keybindings](https://herdr.dev/docs/configuration/#custom-command-keybindings)
- [Socket API](https://herdr.dev/docs/socket-api/)
- [CLI environment variables](https://herdr.dev/docs/cli-reference/#environment-variables)
- [Persistence and remote access](https://herdr.dev/docs/persistence-remote/)
- [Herdr v0.7.5 foreground-client implementation](https://github.com/herdrdev/herdr/blob/v0.7.5/src/server/headless.rs)
