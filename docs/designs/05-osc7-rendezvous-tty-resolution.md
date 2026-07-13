# OSC 7 Rendezvous TTY Resolution

## Status

Accepted

## Decision Summary

The daemon resolves a tty to its Ghostty terminal deterministically: it writes an OSC 7 working-directory nonce to the caller's tty device, scans Ghostty's scripting tree for the terminal whose `working directory` reports that nonce, restores the real value, and binds. The focused-terminal heuristic — trusting a client's `focused: true` claim to bind cache misses to whatever terminal happens to be focused — is excised from the daemon, the protocol, every SDK, and the nvim plugin. When Ghostty 1.4.0 ships its AppleScript `tty` property, the daemon prefers direct lookup via a runtime capability probe and the rendezvous becomes dead code to delete. Retry-safe terminal actions additionally self-heal: an action that fails because the cached terminal no longer exists clears the binding, re-resolves, and retries once, daemon-side.

## Problem Statement / Background

Design 04 fixed tty→terminal binding for daemon-spawned terminals (spawn tokens) and named the remaining gap: organic terminals still bind on a cache miss by trusting the caller's `focused: true` claim against whatever `front window → selected tab → focused terminal` resolves to _at daemon processing time_. The claim is unverifiable and the timing is wrong by construction — a client asserts focus at send time, the daemon evaluates focus at resolve time, and any focus movement in between binds the tty to the wrong terminal for the cache TTL (12 hours).

This stopped being theoretical. Observed live, from the daemon log: an nvim pane's cache entry expired overnight; the user switched to its tab and immediately clicked a sibling pane; nvim's `FocusGained` autocmd fired during the transition and sent `key-table-activate` with `focused: true`; the daemon hit the expired cache, resolved "focused" to the sibling, bound `ttys008` to it, and activated the nvim key table on the sibling pane — which then swallowed `ctrl+hjkl` as raw text while the real nvim pane fell back to `goto_split`. The same race re-poisoned a second tty (`ttys007`) against an ephemeral pane minutes later. Restarting nvim does not help: the cache is keyed by tty, and the tty outlives the process.

Two adjacent failure modes surfaced in the same investigation:

- **Dead-pane bindings fail hard.** When a mis-bound (or legitimately closed) terminal disappears, actions against the cached id fail with `object not found`. The daemon cleared the entry but still failed the request; the client saw an error that the daemon had all the information to heal.
- **Recycled ptys are fast.** A pty released by a closed pane was observed reassigned to a new split within hours. Design 04's claim-overwrite covers daemon-spawned terminals; organic terminals inherited the dead entry until TTL.

Stable Ghostty (1.3.1) exposes only `id`, `name`, and `working directory` on the terminal scripting class. Ghostty tip has `tty` and `pid` (ghostty#11592, milestone 1.4.0, sdef codes `Gtty`/`Gpid` confirmed on main), which permits direct resolution — but 1.4.0 is unreleased and running nightly is declined. The insight that unblocks stable: `working directory` is program-writable over the pty via OSC 7, AppleScript-readable, applied with **no debounce timer**, blocked by **no override mechanism**, and its path is **never checked for existence** (verified in source and live). That is a deterministic side channel from a tty to its terminal, available today.

Verified end-to-end against real Ghostty 1.3.1: a foreign process wrote an OSC 7 nonce to a scratch split's tty; a scripting-tree scan matched the nonce to the terminal on the first poll (119ms including `osascript` process startup, which the daemon does not pay); the identity matched spawn-token ground truth exactly; the real cwd (read from the tty's foreground process) restored exactly.

## Goals

- A tty resolves to its terminal by ground truth on stable Ghostty 1.3.1, regardless of focus, timing, or client honesty.
- A cache entry can never be created that was not true at creation time; entries that become false (pane closed) self-heal on the next retry-safe action.
- The `focused` claim disappears from every layer: daemon, protocol, CLI, Go/TypeScript/Lua SDKs, nvim plugin.
- The rendezvous is one seam behind the same resolver interface the Ghostty 1.4.0 `tty` property will implement; upgrade day requires no release, and the excision afterwards deletes code without changing shape.

## Non-Goals

- Removing spawn tokens (design 04). They keep daemon-spawned terminals pre-warmed with zero resolution cost and are already structured for their own excision at 1.4.0.
- Verifying cache hits on read-only requests (`terminal-id` may return a dead id; the consumer's next retry-safe action heals it).
- Binding ttys that no Ghostty terminal owns (tmux inner ptys, ssh remotes). The rendezvous times out and reports `terminal_not_found` — honest, and strictly better than guessing.
- Protocol backward compatibility or a version bump. Requiring `tty` deliberately changes the v1 wire contract in place rather than preserving the focused-terminal fallback.

## Exposed Shape

- Protocol: `focused` is removed from every terminal-targeted request, and `tty` is required on every one — including `terminal-id` and `tab-terminal-count`, whose no-tty forms previously resolved the focused terminal. No focus-derived resolution path survives anywhere in the daemon. `terminal-id` keeps `refresh`, now meaning "clear this tty's binding and re-resolve" with no focused-window precondition.
- CLI: unchanged surface. `gty` commands already send the caller's tty; they simply stop computing and sending the claim. `gty terminal-id --refresh` works from anywhere.
- SDKs: `focused` options/fields removed from Go, TypeScript, and Lua terminal options. `tty` stays optional at the SDK surface: each SDK derives the caller's own (`GTY_TTY`, then the process's controlling terminal) when omitted, so the wire always carries one.
- nvim plugin: the `focused` config option is removed.
- Daemon behavior, observable: a cache-miss resolution briefly sets the pane's reported working directory to `/gty-rendezvous/<uuid>` and restores it; on never-titled panes (title derived from pwd) the nonce may flash in the tab title for the rendezvous duration. Misses happen once per tty per TTL, or after a pane dies.

## Design Decisions

### 1. The nonce channel is OSC 7 working directory, not the title

Both `name` (OSC 0/2) and `working directory` (OSC 7) are the only program-writable, AppleScript-readable properties on stable. The title loses on every axis, verified in Ghostty source: title updates coalesce through a 75ms timer before the scripting value changes; a manual title override or static `title` config silently discards OSC title writes (rendezvous would hang until timeout); and the title is the most visible string in the UI. OSC 7 applies immediately (direct property assignment, no timer), nothing blocks it, the payload path is parsed but never statted, and it is invisible except on panes that have never set a title, where Ghostty derives the title from the pwd — a sub-second flash on a cache miss, re-derived on restore.

The nonce is `file://localhost/gty-rendezvous/<uuid>`. Ghostty requires the URI host be `localhost` or the exact machine hostname; `localhost` is accepted unconditionally and avoids hostname-drift edge cases.

### 2. Restore comes from the kernel, not from Ghostty

The daemon cannot read the pane's prior `working directory` before the rendezvous — knowing which pane to read is the problem being solved. Instead the restore value is the cwd of the tty's foreground process group, which is exactly the fact OSC 7 exists to report. If the foreground cwd is unreadable (leader exited mid-rendezvous), the daemon writes an empty OSC 7, which Ghostty defines as a pwd reset — a clean unknown, never a wrong value.

Found during implementation: `tcgetpgrp` refuses ttys the caller does not control (returns `ENOTTY` from a foreign process), which silently degraded every restore to the empty reset. The foreground pgid comes from `sysctl KERN_PROC_TTY` instead — the same source `ps -t` reads — with the pgid leader's cwd via `proc_pidinfo`, falling back through other members of the foreground group if the leader is gone.

### 3. Runtime capability probe prefers the 1.4.0 `tty` property

On first resolution the daemon probes the terminal class for the `tty` property (`Gtty`, confirmed in the merged sdef on Ghostty main). Supported → every resolution is a direct scripting-tree scan matching `tty`, no pty writes at all. Unsupported → rendezvous. The result is memoized for the daemon's lifetime; a Ghostty upgrade restarts everything anyway. Both paths share the same tree walker and return the same `TerminalContext` (terminal, window, tab ids), so the eventual excision deletes the rendezvous branch and nothing else.

### 4. The focused claim is excised, not deprecated — and focus resolution with it

With deterministic resolution there is nothing left for the claim to do — a trust knob with no remaining consumer is a standing invitation to reintroduce the bug. The daemon drops the field from every request type and makes `tty` mandatory without a compatibility path or protocol version bump. The CLI/SDK plumbing that computed or carried the claim is deleted.

The last focus-derived path went with it: `tty` became a required field on every terminal-targeted request, and `focusedTerminalContext` was deleted from the control layer entirely. "Resolve whatever is focused" was the seed of every binding bug this design exists to kill; SDKs still derive the caller's tty automatically, so no legitimate caller loses anything.

### 5. Retry-safe actions self-heal once

When a retry-safe terminal action fails because the resolved terminal no longer exists, the daemon clears the tty's cache entry, re-resolves through the same deterministic path, and retries the action once. Retry safety is explicit: single-event and read-only actions opt in; multi-event operations such as input and split fail without replay because an earlier step may already have committed. This closes the recycled-pty hole without duplicating partial side effects. A retry against a re-resolved terminal that fails again reports the error honestly.

### 6. The cache and its TTL are now only an optimization

Resolution is deterministic, so the 12-hour TTL bounds memory and read-only staleness, not correctness. It stays as-is. `clear-cache` remains the manual escape hatch.

## Edge Cases & Failure Modes

- **tty path is not a terminal device, is unwritable, or is gone:** resolution fails with `terminal_not_found` before any OSC write. The pty existing is a precondition of the caller's own request.
- **tty not owned by any Ghostty terminal** (tmux inner pty, foreign terminal emulator): nonce never appears; rendezvous times out (2s budget, 25ms poll interval) → `terminal_not_found`. Never a wrong binding.
- **Pane's own program emits OSC 7 mid-rendezvous** (shell prompt hook racing the scan): the daemon re-asserts the nonce before every poll, so a competing writer costs polls, not the attempt — the rendezvous wins at the pane's first quiet gap. A program emitting OSC 7 in a tight loop for the whole budget still times out; the failure is an error, never a mis-bind.
- **Pane in the press-any-key exited state:** the terminal object still resolves via AppleScript but its pty has no reader; the nonce never renders → timeout. Correct: that pane cannot be the caller's.
- **Never-titled pane:** OSC 7 drives the derived tab title, so the nonce path flashes for the rendezvous duration and the restore re-derives the real one. Cosmetic, miss-only, accepted.
- **Foreground process group leader exited:** restore degrades to the empty-OSC 7 pwd reset.
- **Concurrent resolutions:** distinct ttys mint distinct nonces and match exactly; same-tty requests serialize on the daemon's command queue.
- **Slow pty drain (full master buffer):** the tty fd is opened non-blocking; a write that cannot complete fails the resolution rather than wedging the command queue.
- **Bridge endpoints:** unaffected — a bridge is bound to one terminal at creation and never resolves ttys.
- **Ghostty restart mid-TTL:** all terminal ids die together; the first retry-safe action per tty hits the self-heal path and rebinds.

## Alternatives

### Ghostty nightly for the `tty` property today

- **Status:** Rejected
- **Decision:** The property is exactly right (this design's decision 3 adopts it the day 1.4.0 ships), but running nightly as a daily driver is declined, and GhosttyKit targets stable.

### Title-nonce rendezvous (OSC 0/2)

- **Status:** Rejected
- **Decision:** Same rendezvous shape, worse channel: 75ms coalescing before the scripting value updates, silently discarded under manual title overrides and static `title` config, and visible in the tab bar on every miss. OSC 7 dominates it on latency, reliability, and visibility.

### Keep the focused heuristic, harden it

- **Status:** Rejected
- **Decision:** Double-resolving focus with a delay, comparing before/after, or requiring the claim only on interactive commands all shrink the race window without closing it — and the failure mode remains a silent 12-hour mis-bind. An unverifiable claim cannot be hardened into ground truth.

### Wait for Ghostty 1.4.0

- **Status:** Rejected
- **Decision:** The mis-binding is live today and was observed poisoning two ttys in one evening. The rendezvous is small, verified against real 1.3.1, and shares its interface with the successor.

## Implementation Plan

- [x] Phase 1: Deterministic resolver in the daemon
  - Goal: `CommandContext.terminal(for:)` resolves misses via the capability probe → direct `tty` lookup or OSC 7 rendezvous; the focused parameter and heuristic are gone from the daemon.
  - Files: `GhosttyControl.swift` (scripting-tree walker, `terminalContext(forTTY:)`, `Gtty` probe), `TTYRendezvous.swift` (pty writer, foreground cwd), `CommandContext.swift`, `Requests.swift` (drop `focused` fields, simplify `terminal-id` refresh), `Tests/ghosttykitdTests`.
  - Validation: `just test-swift`; live: cold-cache `gty terminal-id --tty /dev/ttys017` (unfocused organic pane) resolved its exact terminal in 83ms and restored the reported cwd byte-for-byte; a pty owned by no Ghostty terminal returned `terminal_not_found`.
  - Notes: the bulk `every terminal` scan's absolute-ordinal payload is a native-order OSType — big-endian earns `errAECoercionFail` from Cocoa scripting (captured via `AEDebugSends` against what AppleScript itself sends).

- [x] Phase 2: Self-healing actions
  - Goal: object-not-found on a retry-safe terminal action clears the binding, re-resolves, retries once; multi-event actions never replay.
  - Files: `Requests.swift` (opt-in retry policy in `commandReply`), `GhosttyControl.swift` (expose the not-found discriminator), daemon tests.
  - Validation: `just test-swift`; live: key-table activate through a stale binding logged `retrying after stale terminal binding`, re-resolved, and — the pane being genuinely closed — reported `terminal_not_found` honestly; the rebind-success variant is covered by `testStaleBindingHealsWithinOneRequest`.

- [x] Phase 3: Client excision
  - Goal: no layer computes, carries, or documents the claim.
  - Files: `sdk/go/protocol`, `sdk/go/client`, `cli/gty` (drop `terminalTarget`), `sdk/ts`, `sdk/lua`, `nvim/lua/ghosttykit` (+ specs), SDK/nvim docs.
  - Validation: `just check`.

- [x] Phase 4: Docs and smoke closeout
  - Goal: protocol/daemon/cli docs describe deterministic resolution; the smoke script resolves the invoking terminal's real tty (a synthetic tty can no longer bind); this doc moves to Accepted with boxes checked.
  - Files: `docs/protocol.md`, `docs/daemon.md`, `docs/cli.md`, `scripts/smoke-real-daemon.sh`.
  - Validation: `just check`; `just smoke-real-daemon`; `just smoke-real-daemon --bridge`.
