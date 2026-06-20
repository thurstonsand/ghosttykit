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
just fmt-go
just fmt-swift
just fmt-pi
just fmt-nvim
just fmt-docs
just lint-go
just lint-swift
just lint-pi
just lint-lua
just lint-nvim
just lint-docs
just typecheck-go
just typecheck-swift
just typecheck-lua
just typecheck-pi
just typecheck-nvim
just test-go
just test-swift
just test-lua
just test-nvim
just build-go
just build-swift
just build-lua
just build-pi
just build-nvim
```

- `pi/pi-paste` checks require `node_modules`. Use this if dependency issues arise:

```sh
just install-deps-pi
```
