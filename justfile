set shell := ["bash", "-euo", "pipefail", "-c"]

_default:
    just --list

# Format all components.
fmt: fmt-go fmt-swift fmt-lua fmt-nvim fmt-pi fmt-ts fmt-docs

fmt-go:
    just -f sdk/go/justfile fmt
    just -f cli/gty/justfile fmt

fmt-swift:
    just -f daemon/ghosttykitd/justfile fmt

fmt-lua:
    just -f sdk/lua/justfile fmt

fmt-pi:
    if [ -d pi/pi-paste/node_modules ]; then just -f pi/pi-paste/justfile fmt; else echo 'pi/pi-paste: skipping fmt; run just ensure-deps-pi'; fi

fmt-ts:
    if [ -d sdk/ts/node_modules ]; then just -f sdk/ts/justfile fmt; else echo 'sdk/ts: skipping fmt; run just ensure-deps-ts'; fi

fmt-nvim:
    just -f nvim/justfile fmt

fmt-docs:
    if command -v prettier >/dev/null 2>&1; then prettier --write "**/*.md"; else echo 'docs: skipping prettier; install prettier'; fi
    if command -v markdownlint-cli2-fix >/dev/null 2>&1; then markdownlint-cli2-fix; else echo 'docs: skipping markdownlint fix; install markdownlint-cli2'; fi

# Lint all components.
lint: lint-go lint-swift lint-lua lint-nvim lint-pi lint-ts lint-docs

lint-go:
    just -f sdk/go/justfile lint
    just -f cli/gty/justfile lint

lint-swift:
    just -f daemon/ghosttykitd/justfile lint

lint-lua:
    just -f sdk/lua/justfile lint

lint-pi:
    if [ -d pi/pi-paste/node_modules ]; then just -f pi/pi-paste/justfile lint; else echo 'pi/pi-paste: skipping lint; run just ensure-deps-pi'; fi

lint-ts:
    if [ -d sdk/ts/node_modules ]; then just -f sdk/ts/justfile lint; else echo 'sdk/ts: skipping lint; run just ensure-deps-ts'; fi

lint-nvim:
    just -f nvim/justfile lint

lint-docs:
    if command -v markdownlint-cli2 >/dev/null 2>&1; then markdownlint-cli2; else echo 'docs: skipping lint; install markdownlint-cli2'; fi

# Typecheck all components.
typecheck: typecheck-go typecheck-swift typecheck-lua typecheck-nvim typecheck-pi typecheck-ts

typecheck-go:
    just -f sdk/go/justfile typecheck
    just -f cli/gty/justfile typecheck

typecheck-swift:
    just -f daemon/ghosttykitd/justfile typecheck

typecheck-lua:
    just -f sdk/lua/justfile typecheck

typecheck-pi:
    if [ -d pi/pi-paste/node_modules ]; then just -f pi/pi-paste/justfile typecheck; else echo 'pi/pi-paste: skipping typecheck; run just ensure-deps-pi'; fi

typecheck-ts:
    if [ -d sdk/ts/node_modules ]; then just -f sdk/ts/justfile typecheck; else echo 'sdk/ts: skipping typecheck; run just ensure-deps-ts'; fi

typecheck-nvim:
    just -f nvim/justfile typecheck

# Test all components with tests.
test: test-go test-swift test-lua test-nvim test-ts

test-go:
    just -f sdk/go/justfile test
    just -f cli/gty/justfile test

test-swift:
    just -f daemon/ghosttykitd/justfile test

test-lua:
    just -f sdk/lua/justfile test-all

test-nvim:
    just -f nvim/justfile test

test-ts:
    if [ -d sdk/ts/node_modules ]; then just -f sdk/ts/justfile test; else echo 'sdk/ts: skipping test; run just ensure-deps-ts'; fi

# Build binaries and build-check non-binary packages.
build: build-go build-swift build-lua build-nvim build-pi build-ts

build-go:
    just -f cli/gty/justfile build

build-swift:
    just -f daemon/ghosttykitd/justfile build

build-lua:
    just -f sdk/lua/justfile build

build-pi:
    if [ -d pi/pi-paste/node_modules ]; then just -f pi/pi-paste/justfile build; else echo 'pi/pi-paste: skipping build; run just ensure-deps-pi'; fi

build-ts:
    if [ -d sdk/ts/node_modules ]; then just -f sdk/ts/justfile build; else echo 'sdk/ts: skipping build; run just ensure-deps-ts'; fi

build-nvim:
    just -f nvim/justfile build

# Validate GitHub Actions workflows.
check-github-actions:
    actionlint

# Validate dependency update configuration.
check-renovate:
    renovate-config-validator renovate.json

# Run all checks.
check: fmt lint typecheck test build check-github-actions check-renovate

# Exercise daemon/cli against the focused Ghostty window. Mutates split layout, focus, resize, zoom, key table, cache, and pasteboard.
smoke-real-daemon *args: build-go build-swift
    scripts/smoke-real-daemon.sh {{args}}

# Ensure local development dependencies are present and current.
ensure-deps: ensure-deps-lua ensure-deps-nvim ensure-deps-ts ensure-deps-pi

ensure-deps-lua:
    @if [ ! -d .luals/addons/busted ] || [ ! -d .luals/addons/luassert ] || [ ! -e .luals/nvim-runtime ]; then rm -f .luarocks/.ghosttykit-lua-deps.sha; fi
    @scripts/ensure-lua-deps.sh .luarocks/.ghosttykit-lua-deps.sha install-deps-lua sdk/lua/ghosttykit-scm-1.rockspec sdk/lua/justfile

ensure-deps-nvim: ensure-deps-lua
    @if [ ! -d .luarocks/lib/luarocks/rocks-5.1/ghosttykit.nvim ]; then rm -f .luarocks/.ghosttykit-nvim-deps.sha; fi
    @scripts/ensure-lua-deps.sh .luarocks/.ghosttykit-nvim-deps.sha install-deps-nvim nvim/ghosttykit.nvim-scm-1.rockspec nvim/justfile

ensure-deps-ts:
    @scripts/ensure-node-deps.sh sdk/ts install-deps-ts

ensure-deps-pi: ensure-deps-ts
    @scripts/ensure-node-deps.sh pi/pi-paste install-deps-pi

# Force reinstall local development dependencies.
install-deps: install-deps-lua install-deps-nvim install-deps-ts install-deps-pi

install-deps-lua:
    just -f sdk/lua/justfile install-deps

install-deps-nvim:
    just -f nvim/justfile install-deps

install-deps-pi:
    just -f pi/pi-paste/justfile install-deps

install-deps-ts:
    just -f sdk/ts/justfile install-deps

update-deps: update-deps-mise update-deps-go

update-deps-mise:
    mise upgrade --bump --local --exclude lua

update-deps-go:
    just -f sdk/go/justfile update-deps
    just -f cli/gty/justfile update-deps
