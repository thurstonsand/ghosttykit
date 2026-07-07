# Direct AppleEvents Ghostty Control

## Status

Accepted

## Decision Summary

Replace Ghostty-facing `NSAppleScript` source-string control in `ghosttykitd` with direct descriptor-based AppleEvents. Keep System Events AppleScript for macOS window geometry used by percent resize, because replacing it with Accessibility adds a new permission and a fragile cross-API window mapping for a modest latency win.

## Problem Statement

`ghosttykitd` currently controls Ghostty by building AppleScript source strings and executing them with `NSAppleScript`. This works, but every call reparses source and user-controlled values must be interpolated into script text. A spike showed that Ghostty's scripting dictionary can be driven directly with AppleEvent descriptors, which avoids source-string escaping risk and improves latency for core operations.

The migration needs to preserve the public daemon protocol while containing the low-level AppleEvent machinery behind a small internal interface.

## Goals

- Replace Ghostty scripting operations with direct AppleEvents.
- Keep `GhosttyControlling` unchanged so request handling and tests remain stable.
- Encapsulate four-character codes, object specifiers, descriptor extraction, and OSStatus handling behind a small private layer.
- Surface friendly localized errors instead of raw AppleEvent reply records where practical.
- Preserve the existing System Events AppleScript path for window size lookup in percent resize.

## Non-Goals

- Do not add Accessibility permission in this migration.
- Do not change the daemon wire protocol or client behavior.
- Do not edit the standalone extraction design doc; keep this migration as a separate decision artifact.
- Do not attempt to support older Ghostty scripting dictionaries beyond reporting clear failures.

## Design Decisions

### 1. Use direct AppleEvents for Ghostty control

Ghostty's `sdef` exposes the same operations through AppleEvent command and property codes that AppleScript uses. The migration will send those events directly with `NSAppleEventDescriptor` instead of compiling AppleScript source strings.

Representative spike timings against a live Ghostty instance showed meaningful wins:

```text
script focused context:        median 53.263ms, p95 74.219ms
cached script focused context: median 50.068ms, p95 73.403ms
direct focused context:        median 24.992ms, p95 29.632ms

script perform action:         median 16.676ms, p95 36.716ms
cached script perform action:  median 16.679ms, p95 36.508ms
direct perform action:         median  8.322ms, p95  9.041ms
```

Caching `NSAppleScript` instances did not recover the gap. Direct AppleEvents also avoid interpolating terminal ids, commands, working directories, and action strings into AppleScript source.

### 2. Keep a swappable low-level control seam

The implementation should be layered:

```text
AppleEventGhosttyController
  -> GhosttyAppleEvents
      -> AppleEventClient / descriptor helpers
  -> SystemEventsWindowGeometry
```

`AppleEventGhosttyController` implements `GhosttyControlling` and speaks in project concepts. `GhosttyAppleEvents` exposes a minimal Ghostty-shaped API. `AppleEventClient` owns descriptor construction, sending, reply extraction, and OSStatus mapping.

This shape keeps the controller readable and leaves room to swap the low-level implementation later if AppleScript or another control plane becomes preferable for a subset of operations.

### 3. Keep System Events AppleScript for window geometry

Percent resize needs the macOS Ghostty window width or height. Ghostty's scripting dictionary exposes window identity but not window size.

A spike proved Accessibility can read `AXSize` very quickly, but mapping Ghostty scripting window ids to Accessibility windows has no stable public join key. The public bridge is effectively window ordering, optionally checked by title, followed by caching the `AXUIElement`. That adds a new Accessibility permission, mapping race handling, docs, and doctor behavior for a secondary path.

Measured comparison:

```text
System Events dimension:      median 39.299ms, p95 61.944ms
direct index + AX dimension:  median 24.989ms, p95 29.834ms
```

The improvement is not worth the new permission and mapping complexity in this migration. The System Events path should remain clearly isolated as `SystemEventsWindowGeometry`.

### 4. Map AppleEvent failures to friendly errors

Direct AppleEvents can fail with low-level OSStatus codes and reply records. The private AppleEvent layer should translate common failures into localized domain-oriented messages:

- `procNotFound` / invalid connection: Ghostty is not running or unavailable.
- `errAEEventNotPermitted`: Automation permission denied.
- `errAEEventWouldRequireUserConsent`: Automation consent required.
- `errAEEventNotHandled`: Ghostty scripting API does not support the requested operation.
- `errAENoSuchObject`: requested Ghostty object no longer exists.
- `errAECoercionFail`: invalid descriptor or scripting dictionary mismatch.

Raw reply records may still be useful for logs, but request responses should not expose inscrutable AppleEvent internals when a clearer message is available.

### 5. Rename the implementation file

Rename `AppleScript.swift` to `GhosttyControl.swift`. The file will contain both direct AppleEvents control and the isolated System Events window geometry helper, so the old filename is no longer accurate.

## Edge Cases & Failure Modes

- **Ghostty is not running:** preflight returns false; commands fail with a clear Ghostty-unavailable message.
- **Automation permission denied:** command failures should mention Automation permission rather than leaking `-1743` alone.
- **Ghostty scripting dictionary changes:** unsupported commands or descriptor coercion failures should point to an unsupported or changed scripting API.
- **Cached terminal context references a closed terminal:** object resolution failure should surface as a missing Ghostty object/terminal instead of a raw `-1728`.
- **Percent resize uses System Events:** failures remain possible if System Events automation is denied; this remains the existing behavior and permission model.

## Rejected Alternatives

### Cache `NSAppleScript` instances

`NSAppleScript` can be compiled and reused, but benchmarks showed almost no improvement for the representative calls. It also preserves source-string interpolation risk and becomes awkward for dynamic arguments.

### Replace System Events with Accessibility

Accessibility reads window sizes far faster than System Events, but the complete safe path still requires joining Ghostty scripting windows to Accessibility windows. Public macOS APIs expose no stable shared identifier. Adding Accessibility permission and mapping complexity is not justified by the percent-resize latency savings.

### Use private `_AXUIElementGetWindow`

Private Accessibility functions can map an AX window to a CoreGraphics window id, but they are not public API and still do not directly join to Ghostty's scripting window id. This is too brittle for GhosttyKit.

## Integration Points

- `GhosttyControlling`: remains the public internal protocol consumed by request handling.
- `AppleEventGhosttyController`: replaces `AppleScriptGhosttyController` as the real daemon controller.
- `DryRunGhosttyController`: remains unchanged for dry-run behavior.
- `SystemEventsWindowGeometry`: owns the remaining System Events AppleScript call for percent resize.
- `docs/tcc-macos.md`: no behavior change in this migration; Automation remains the required permission class.

## Implementation Plan

- [x] Phase 1: Direct AppleEvent control layer
  - Goal: Add the direct AppleEvent implementation while preserving `GhosttyControlling` behavior.
  - Files: `daemon/ghosttykitd/Sources/ghosttykitd/AppleScript.swift` renamed to `GhosttyControl.swift`; `daemon/ghosttykitd/Sources/ghosttykitd/App.swift`.
  - Work:
    - Rename `AppleScriptGhosttyController` to `AppleEventGhosttyController`.
    - Add `GhosttyAppleEvents`, `AppleEventClient`, AppleEvent code constants, descriptor helpers, and friendly error mapping.
    - Port focused context, tab terminal count, action execution, split, focus, preflight, and Ghostty window index to direct AppleEvents.
    - Keep pasteboard and dry-run behavior unchanged.
    - Update daemon dry-run help text if it still says AppleScript APIs.
  - Validation:
    - `just fmt-swift`
    - `just typecheck-swift`
    - `just test-swift`

- [x] Phase 2: System Events geometry isolation
  - Goal: Keep percent resize behavior unchanged while moving System Events AppleScript behind a named helper.
  - Files: `daemon/ghosttykitd/Sources/ghosttykitd/GhosttyControl.swift`.
  - Work:
    - Add `SystemEventsWindowGeometry`.
    - Route percent resize dimension lookup through the helper.
    - Keep resize action execution through direct Ghostty AppleEvents.
  - Validation:
    - `just test-swift`
    - Manual/live smoke if requested: percent resize against real Ghostty.

- [x] Phase 3: Live verification and evidence
  - Goal: Prove the migrated controller works against a live Ghostty instance.
  - Files: no expected source changes unless smoke exposes bugs.
  - Work:
    - Run daemon/client smoke commands that exercise terminal id, tab count, key-table actions, focus/zoom/resize, and split.
    - Compare behavior to the spike expectations.
  - Validation:
    - `just check` if practical.
    - `just smoke-real-daemon` only if explicitly approved because it mutates the focused Ghostty window.
