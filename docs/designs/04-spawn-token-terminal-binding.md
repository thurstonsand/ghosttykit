# Spawn Token Terminal Binding

## Status

Accepted

## Decision Summary

When `ghosttykitd` creates a terminal, it wraps the spawned command so the terminal's first act is to claim its own tty→terminal-id binding with a single-use spawn token — replacing the focused-terminal guess with the ground truth the daemon already holds from the split reply. Ghostty tip (v0.4.0) exposes the terminal's tty over AppleScript, which will obviate tokens entirely; this design is explicitly a bridge for stable Ghostty, structured for excision. Alongside it, splits gain typed-input plumbing (`gty input`) so spawned terminals can run interactive login shells instead of one-shot commands.

## Problem Statement / Background

The daemon maps ttys to Ghostty terminal ids through a cache. On a miss, the only binding mechanism is a heuristic: trust the caller's `focused: true` claim and bind the tty to whichever terminal Ghostty reports as focused at that instant. Two failure modes follow:

- **Focus race at spawn.** `split` spawns the new terminal's command first and grants focus second. A client inside the new terminal (e.g. nvim registering for key-table routing) that resolves its tty inside that gap gets bound to the _previous_ pane. The binding is cached for 12 hours, so nvim's key-table activations land on the wrong terminal until the cache expires — observed in practice as Ghostty routing the nvim keyspace to the agent pane in `ide`-style layouts.
- **Recycled ptys.** Cache entries are never invalidated when terminals close. A new terminal that receives a recycled pty inherits the dead terminal's stale mapping, and a plain `terminal-id` trusts it.

The `ide` script currently works around the race with a bidirectional fifo handshake: the new split blocks until the outer script confirms `split --wait` returned (focus granted), then registers with `--refresh`. It works, but it is client-side choreography compensating for a daemon-side information gap — the daemon _knows_ the new terminal's id from the split AppleEvent reply and throws it away.

A second problem shares the same spawn path: running an editor via `--command "/bin/zsh -ilc 'nvim .'"` gives the surface a non-interactive shell. Shell integration never reports the working directory (session restore falls back to the default directory), and quitting nvim leaves no shell to return to — the surface behaves like it died and respawned. The desired behavior is a plain interactive login shell that nvim runs _inside of_, typed as if by hand.

Ghostty tip exposes the terminal's tty on its scripting class, which permits direct tty→terminal resolution with no cache trust at all. Stable (1.3.1, verified against the installed sdef) exposes only `id`, `name`, and `working directory`. This design does not wait: the keyspace misbinding is live today, and tokens are cheap to excise.

## Goals

- A terminal spawned by the daemon gets a correct tty→terminal-id binding before its command runs, regardless of focus timing — on stable Ghostty, today.
- Clients inside daemon-spawned terminals need no registration step, no handshake, and no changes — their first request hits a warm cache.
- Steady-state requests carry no new fields and pay no new checks; all token machinery is confined to the spawn moment and structured for later removal.
- Daemon-spawned editor panes run real interactive login shells: quitting the program returns to the shell, and session restore recovers the true working directory.
- Consumers like the `ide` script shrink to plain sequential commands.

## Non-Goals

- Binding terminals the daemon did not spawn (organic cmd+D splits, manual tabs). The focused heuristic remains for those until direct tty lookup lands.
- Remote/bridge binding. Bridge endpoints are already bound to one terminal; the protocol invariant that remote callers never provide trusted terminal identity stands.
- Removing the focused heuristic, `--refresh`, or the tty cache in this design.
- Waiting for Ghostty v0.4.0 stable, or requiring nightly builds.

## Exposed Shape

- `gty split --wait` prints the new terminal's **tty** (the ack reply's `value`). Terminal ids never cross the protocol surface; `gty terminal-id` remains the sole escape hatch.
- `gty input <text>` — sends text to a terminal as pasted input, targeted by the existing `--tty` override or the caller's own tty; `--submit` follows it with an enter keypress. Text arrives via bracketed paste, so without `--submit` it sits in the line editor unexecuted.
- `gty spawn-claim <token>` — plumbing invoked by the daemon's wrapper, hidden from cobra help. Sends the caller's tty and the token; the daemon binds and burns.
- Protocol additions: `spawn-claim` and `input` requests, a `spawn_token_not_found` error code, and a populated `value` on split ack replies.
- Observable side effect: a spawned terminal's process is briefly `/bin/sh -c 'gty spawn-claim … ; exec …'` before the `exec` erases it. The token is visible in `ps` during that window; claiming still requires local daemon socket access, so this exposes nothing the same-user trust domain doesn't already have.

## Design Decisions

### 1. Claim at spawn, not at first request

The daemon wraps every spawned command so the claim happens synchronously before anything else runs in the terminal:

```sh
/bin/sh -c 'GTY_SOCK=<socket> <gty> spawn-claim <token> >/dev/null 2>&1; exec <target>'
```

The socket is pinned to the minting daemon's own because Ghostty-spawned processes do not inherit the daemon's environment — a daemon on a non-default socket (smoke tests, development) would otherwise mint tokens its wrappers claim against the wrong endpoint.

The wrapper's tty is the same pty every descendant inherits, so the binding it writes is correct for the terminal's whole lifetime. By the time nvim (or anything else) makes its first request, resolution is a plain cache hit.

This was chosen over injecting a `GTY_SPAWN_TOKEN` env var for clients to present on their requests: the env var outlives its one-time purpose, every descendant re-presents a burned token on every request forever, and all four hand-maintained protocol implementations (Go, Swift, TS, Lua) would need token plumbing. Claim-at-spawn touches zero SDKs and adds zero steady-state cost.

`;` rather than `&&`: if the claim fails for any reason, the target must still run. Failure degrades to today's lazy heuristic binding, never to a broken terminal.

### 2. Every daemon spawn is wrapped, command or not

When `split` carries `--command`, the wrapper execs it. When it doesn't, the wrapper execs the user's login shell (`exec -l <shell>`, resolved from the user record via `getpwuid` — the same DirectoryServices source `dscl` reads — with `$SHELL`/`/bin/zsh` fallback) — an interactive login shell claimed and indistinguishable from one the user opened by hand: shell integration active, working directory reported, prompt waiting. Uniform coverage means every daemon-spawned terminal binds deterministically, including editor panes that deliberately spawn bare shells.

Tradeoff: Ghostty's `command` config option (in `~/.config/ghostty/config`) replaces the default shell for every new surface; a user who sets it (fish-without-chsh, tmux attach) gets their login shell instead of that command in daemon-spawned bare splits, because the wrapper occupies the surface's command slot. Accepted — daemon spawns are programmatic surfaces, and the alternative (no claim on bare splits) leaves the most important case unbound.

### 3. Editor-style spawns use typed input, not command strings

To run a program in a spawned terminal _without_ sacrificing the interactive shell, callers split bare (login shell, claimed) and then `gty input --tty <tty> --submit 'nvim .'`. The daemon delivers it via Ghostty's `input text` AppleEvent plus an enter `send key` — verified live: `input text` alone lands in the line editor via bracketed paste and does not execute; the enter keypress submits it.

Consequences: the program appears in shell history as if typed; quitting returns to the shell; OSC 7 has already reported the cwd, so session restore recovers the project directory. The `ide` fifo handshake, `--refresh` sequencing, and `zsh -ilc` wrapper all become deletable.

Slow shell startup does not break delivery: typed-ahead input buffers in the pty until the shell reads it. Verified live against an 8-second `.zshrc` — input sent 2 seconds into startup executed at first prompt.

### 4. Single-use tokens in a rendezvous map, not a cache

The daemon mints an unguessable token (lowercase UUID, matching bridge session-id style) per spawn and holds it in a pending-spawn map: `token → (terminal context, parked --wait reply if any)`. The claim consumes the entry — it warms the tty cache with the ground-truth binding and delivers the tty to a parked split reply. Entries live only for the spawn window: one timeout constant (seconds) bounds both the reply hold and the entry's lifetime. Removal is scheduled when the token is minted and is not owned by any waiter — a fire-and-forget split whose claim never arrives is swept at the same deadline; nothing can stick.

The map exists at all (rather than a pure in-process handoff between the split handler and the claim handler) only because fire-and-forget splits still matter: SDK callers split without `ack`, their claims arrive on separate connections moments later, and those claims must still warm the tty cache even with nobody parked on the reply.

Conceptually a claim is a key upgrade — the same terminal-context value enters keyed by token and lands in the tty cache keyed by tty — and the implementation shares that value type. It is deliberately _not_ one merged map: the key namespaces are different relations, pending entries own connection state (a parked reply) that a data cache must never hold, and the lifetimes differ by four orders of magnitude. Ghostty terminal ids are UUIDs and never reused, so even a pathologically late claim could only write a true fact; the timeout exists to unpark replies and bound the map, not to guard correctness.

A claim on an unknown or timed-out token fails with `spawn_token_not_found` — honest, because `spawn-claim` is an explicit request whose reply nobody chains on. A successful claim **overwrites** any existing cache entry for that tty. This is what retires the recycled-pty staleness for daemon-spawned terminals: the fresh ground-truth binding beats the dead one unconditionally.

### 5. Wrapper escaping: verified against real Ghostty

Ghostty parses the `command` surface-configuration property into the spawned argv with shell-words semantics. Verified empirically on 1.3.1: a wholesale `%q`-style backslash-escaped `/bin/sh -c` script containing single quotes, double quotes, `$`, backslashes, semicolons, and runs of spaces arrived byte-for-byte intact. The daemon composes the full inner script and backslash-escapes it; no reliance on quote characters.

### 6. The daemon resolves the gty binary path itself

Ghostty-spawned processes get a GUI-app PATH without Homebrew, so the wrapper must reference gty absolutely. The daemon resolves gty at startup as a sibling of its own executable (both install to the same prefix), overridable via `GTY_BIN` for development, matching existing test tooling. If no gty is found, the daemon skips wrapping entirely and logs — splits still work, binding falls back to the heuristic.

### 7. Bridges reject spawn-claim

Bridge endpoints answer `spawn-claim` with `invalid_request`. A bridge daemon is already bound to exactly one terminal; accepting tty-binding requests from the remote side would violate the invariant that remote callers never provide trusted Ghostty terminal identity. `input` over a bridge targets only the bridge's bound terminal; explicit targets are rejected the same way.

### 8. Split replies return the new terminal's tty via claim rendezvous

The interface speaks tty everywhere; terminal ids stay an internal implementation detail (`gty terminal-id` is the sole deliberate escape hatch). Stable AppleScript cannot report a new terminal's tty — but the spawn claim carries exactly that fact. So a `split --wait` reply holds until the claim for its token arrives, correlated daemon-side, and returns the claimed tty in the existing `value` field. The claim fires from the wrapper before any shell rc runs, so the rendezvous adds only wrapper-exec latency (well under a second) regardless of how slow the shell's startup is.

If the claim never arrives (gty missing, wrapper failed), the reply returns after a short timeout with an empty `value` — the split still exists; the caller degrades or falls back to `gty terminal-id` from inside. On v0.4.0 the rendezvous is replaced by reading the tty property directly from the split AppleEvent reply; the exposed interface does not change.

### 9. Tokens are a bridge to v0.4.0, structured for excision

Ghostty tip exposes the terminal's tty over AppleScript. Once that reaches stable, the daemon resolves tty→terminal directly per lookup — no cache trust, no heuristic, no tokens. The token machinery is therefore kept excisable: minting and wrapping live in the split path behind one seam, claiming is one request type plus one hidden CLI command, and nothing else in the protocol or SDKs knows tokens exist. Runtime capability detection (probe the terminal class for a tty property; prefer direct lookup when present) is the successor already anticipated by design 01, and its adoption retires decisions 1, 2, 4, and 6 wholesale — and replaces decision 8's rendezvous with a direct property read — without changing anything a client sees.

## Edge Cases & Failure Modes

- **Claim fails (daemon restarted, socket gone, gty missing at spawn):** wrapper's `;` runs the target anyway; the terminal binds lazily via the heuristic on its first focused request. Today's behavior, not worse.
- **Session restore re-runs a wrapper:** the claim fails silently on the long-burned token and the login shell starts in the restored directory. Harmless by construction.
- **Split succeeds but focus/AppleEvent work after minting fails:** the pending entry is removed at the spawn timeout; nothing dangles.
- **Claim never arrives for a waiting split reply:** `split --wait` returns after the spawn timeout with empty `value`; the split exists, the caller degrades — the `ide` script skips launching nvim and leaves a login shell in the right directory.
- **Slow shell startup (direnv, heavy rc):** the claim precedes the shell entirely, and typed input buffers in the pty until first prompt — verified against an 8-second rc.
- **Recycled pty with a stale cache entry:** claim overwrites unconditionally.
- **Duplicate claim (wrapper somehow runs twice, or a descendant replays the argv):** token is burned after first claim; replay gets `spawn_token_not_found` and no state changes. The first claim's cache entry stands.
- **Two concurrent splits:** each mints a distinct token bound to its own terminal id; claims cannot cross.
- **commandText containing quotes, backslashes, or newlines:** wholesale `%q`-style escaping, verified live; no user content is interpreted outside the inner `sh -c` script.
- **`gty input` without `--submit`:** text sits in the line editor as a paste — intentional, callers may compose.
- **`gty input` into a full-screen program (target already running vim, etc.):** delivered as paste to whatever reads the pty; the caller owns targeting. No daemon-side guard.
- **User's login shell unresolvable:** fall back `$SHELL` → `/bin/zsh`.
- **spawn-claim over a bridge:** `invalid_request`. `input` over a bridge is accepted but its tty is ignored — it targets only the bridge's bound terminal, like every bridged terminal command.
- **gty resolving its own tty inside a fresh surface:** macOS `ttyname()` reports the literal `/dev/tty` alias for descriptors opened on `/dev/tty`, which would make the claim bind a useless key. Found during implementation; gty now prefers stdin's terminal name and falls back to `/dev/tty`.

## Alternatives

### Wait for Ghostty v0.4.0 stable instead of building tokens

- **Status:** Rejected
- **Decision:** The keyspace misbinding is live today on stable, the release timeline is not ours, and the token bridge is small and confined behind one seam (decision 9). The `input`/split-reply plumbing is wanted regardless and survives the excision.
- **Discussion:** Running nightly locally was considered and declined; the fallback heuristic would still be the shipped path for stable users either way.

### Env var token (`GTY_SPAWN_TOKEN`) presented on requests

- **Status:** Rejected
- **Decision:** The one-time startup concern leaks into steady state: the env var persists in every descendant process, burned tokens ride every request indefinitely, the daemon checks a token table on every terminal-targeted request, and all four SDK implementations need plumbing. Claim-at-spawn achieves the same determinism with a single plumbing request and no envelope changes.
- **Discussion:** Ghostty's surface configuration supports `environment variables` natively (verified live), so injection without a wrapper is possible — a variant where the user's shell rc claims and unsets the var was also considered, but coupling binding correctness to shell configuration is too weak for a general toolkit mechanism.

### Client-side handshake (status quo splint)

- **Status:** Rejected
- **Decision:** The `ide` script's bidirectional fifo dance — block the split's registration until `split --wait` confirms the focus grant, then `terminal-id --refresh`. Works, but every consumer must reimplement the choreography, `--refresh` still binds by focus guess (correct only because the handshake sequences it), and timeouts paper over failures. It is a client patch for a daemon-side information gap.

### Daemon-side process-tree discovery

- **Status:** Rejected
- **Decision:** Correlating a client tty to a Ghostty surface by walking process ancestry identifies the Ghostty _process_, but nothing maps a pty to a _surface_ without Ghostty's cooperation. Dead end.

### `initial input` surface property instead of post-split `input text`

- **Status:** Rejected
- **Decision:** Verified working (typed-ahead input executes in the spawned shell), but it fires at spawn time — before the focus grant and before the caller can sequence anything — and it cannot target an existing terminal. Post-split `gty input` gives the caller ordering control and doubles as a general capability.
- **Discussion:** Worth remembering for spawn flows that genuinely want fire-and-forget input with no follow-up.

## Implementation Plan

- [x] Phase 1: Inert spawn-claim plumbing
  - Goal: The `spawn-claim` request, hidden CLI command, and rendezvous type exist end-to-end and are fully tested — but nothing mints tokens yet, so every claim honestly answers `spawn_token_not_found`. No user-visible behavior changes.
  - Files: `daemon/ghosttykitd/Sources/ghosttykitd/SpawnRendezvous.swift` (new), `Requests.swift` (request decode/dispatch, bridge rejection), daemon tests; `cli/gty/` new command file (cobra `Hidden: true`), `main.go`; `sdk/go/client` + protocol request constructor; `docs/protocol.md`, `docs/protocol/codes.md` (`spawn_token_not_found`).
  - Work: Rendezvous map with mint/claim/sweep and a parked-reply slot, removal scheduled at mint (one timeout constant); `spawn-claim` request carrying `tty` + `spawn_token`; claim writes through to `TerminalIDCache`, overwriting any existing entry for that tty; bridge endpoints answer `invalid_request`; hidden `gty spawn-claim <token>`.
  - Validation: `just test-swift test-go lint`; manual: `gty spawn-claim deadbeef` exits nonzero with `spawn_token_not_found`.

- [x] Phase 2: Mint, wrap, and the tty reply
  - Goal: Every daemon spawn claims its binding; `gty split --wait` prints the new terminal's tty.
  - Files: `GhosttyControl.swift` (`split` returns the new terminal reference; wrapper composition), `Requests.swift` (`SplitRequest` mints, parks the ack reply on the rendezvous, replies with the claimed tty in `value`), new escaping helper + exhaustive tests, `App.swift` (gty path resolution at startup: sibling of daemon binary, `GTY_BIN` override; skip wrapping + log when absent), `Tests/ghosttykitdTests` doubles.
  - Work: `%q`-style backslash escaper (no quote characters — the verified parsing path); wrapper `/bin/sh -c '<gty> spawn-claim <tok> >/dev/null 2>&1; exec <target>'` where target is the given commandText or `exec -l` of the login shell (dscl → `$SHELL` → `/bin/zsh`); `--wait` replies held on the rendezvous, empty `value` on timeout.
  - Validation: `just test-swift`; live: `gty split right --wait` prints a real `/dev/ttys*` and `gty terminal-id --tty <it>` resolves without `--refresh`; repeated `ide`-style splits bind the nvim keyspace correctly every time; extend `scripts/smoke-real-daemon.sh` to assert a non-empty split `value` (`just smoke-real-daemon`).

- [x] Phase 3: `gty input`
  - Goal: Typed input as a first-class capability: paste text into a terminal by tty, optionally submit with an enter keypress.
  - Files: `GhosttyControl.swift` (AppleEvent wrappers for `input text` / `send key` — codes `GhstInTx`, `GhstSKey`, params `GItT`, `GKeA`, `GKeM`, `GKeT`), `Requests.swift` (`input` request: resolved tty target, `text`, `submit`; bridge targets its bound terminal only), CLI `gty input [--submit] <text>`, `sdk/go`, `docs/protocol.md`, `docs/cli.md`.
  - Work: input delivered as paste (bracketed, does not execute alone — by design), `--submit` sends enter after; smoke coverage.
  - Validation: `just test-swift test-go lint`; live: `tty=$(gty split right --wait); gty input --tty "$tty" --submit 'echo proof'` executes in the split, including against a shell mid-startup.

- [x] Phase 4: Docs and smoke closeout
  - Goal: Repo documentation and the real-daemon exerciser reflect the full feature; design doc moves to Accepted.
  - Files: `docs/daemon.md`, `docs/cli.md`, `scripts/smoke-real-daemon.sh`, this doc's Status.
  - Work: daemon.md behavior list gains spawn claim + input; smoke script exercises split-returns-tty, claim overwrite of a stale binding, and submitted input end-to-end.
  - Validation: `just check`; `just smoke-real-daemon`.

- [x] Coda (ansiblonomicon, separate repo): `ide` script rewrite
  - Goal: The script collapses to sequential commands with no fifos, no timeouts, no `zsh -ilc`.
  - Files: `chezmoi/dot_local/bin/executable_ide`.
  - Work: keep the startup `gty terminal-id --refresh` (the outer pane is organic — the heuristic still covers it) and the pre-split `cols` capture; then `tty=$(gty split left --cwd "$cwd" --wait)`, resize, zoom-if-small, `[[ -n $tty ]] && gty input --tty "$tty" --submit 'nvim .'` — empty tty skips the editor launch and leaves a login shell in the project directory.
  - Validation: live `ide` run: quit nvim → shell with `nvim .` in history; relaunch after a Ghostty restart → tab restores in the project directory; keyspace routes to the editor pane on first try.
