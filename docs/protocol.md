# GhosttyKit Protocol

Status: skeleton.

The v1 protocol is hand-maintained. Each request carries a protocol version field. Language implementations are maintained directly in Go, Swift, TypeScript, and Lua as needed; no schema/code generation source of truth exists in v1.

Core invariants:

- Remote callers never provide trusted Ghostty terminal identity.
- `GTY_SOCK` is a bearer endpoint that routes to a daemon-owned bridge session.
- Lease messages require a local-only lease token.
- Request messages do not receive or require the lease token.
