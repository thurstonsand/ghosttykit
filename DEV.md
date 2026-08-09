# Development

## Code style

- Comments, outside those standardized in the language, should only ever be added to explain non-obvious decisions or surprising behavior.
- Prefer top-down code organization:
  - exported entry points and primary behavior first
  - helpers after first use where practical
  - exported API types near the top

## Verification commands

Tasks live in `mise.toml` at the repo root and in one `mise.toml` per component. The root is a mise monorepo root, so every component task is addressable as `//<component>:<task>` from anywhere in the checkout.

- Root commands:

```sh
mise tasks --all
mise run fmt # prefer this over language-native formatter binaries
mise run fmt:check
mise run lint
mise run typecheck
mise run test
mise run build
mise run check
mise run smoke-real-daemon  # mutates the focused Ghostty window; use only when requested
mise run smoke-real-daemon --bridge  # same checks through a daemon-owned bridge socket
```

- Component commands. The components are `//cli/gty`, `//daemon/ghosttykitd`, `//nvim`, `//pi/pi-paste`, `//sdk/go`, `//sdk/lua`, and `//sdk/ts`:

```sh
mise run //sdk/go:test          # one task in one component
mise run //sdk/lua:check        # that component's whole check
mise run '//...:lint'           # one task across every component that defines it
mise run '//sdk/lua:test:*'     # every subtask in a group
```

```sh
mise run deps:lua   # shared Lua rock tree and language-server type stubs
mise run deps:nvim  # Neovim plugin rock dependencies
mise run deps:ts    # TypeScript SDK dependencies
mise run deps:pi    # Pi paste dependencies
```
