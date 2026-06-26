# Development

## Code style

- Comments, outside those standardized in the language, should only ever be added to explain non-obvious decisions or surprising behavior.
- Prefer top-down code organization:
  - exported entry points and primary behavior first
  - helpers after first use where practical
  - exported API types near the top

## Verification commands

- Root commands:

```sh
just --list
just fmt # prefer this over language-native formatter binaries
just fmt-check
just lint
just typecheck
just test
just build
just check
just smoke-real-daemon  # mutates the focused Ghostty window; use only when requested
just smoke-real-daemon --bridge  # same checks through a daemon-owned bridge socket
```

- Component commands:

```sh
just fmt-{go,swift,lua,pi,ts,nvim,docs}
just fmt-check-{go,swift,lua,pi,ts,nvim,docs}
just lint-{go,swift,lua,pi,ts,nvim,docs}
just typecheck-{swift,lua,pi,ts,nvim}
just test-{go,swift,lua,ts,nvim}
just build-{go,swift,lua,pi,ts,nvim}
```

- Lua and Node checks require local package dependencies. Use these if dependency issues arise:

```sh
just install-deps-lua # Lua SDK and Neovim plugin dependencies
just install-deps-ts  # TypeScript SDK plus Pi paste dependencies
```
