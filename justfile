set shell := ["bash", "-euo", "pipefail", "-c"]

_default:
    just --list

# Format all components.
fmt: fmt-go fmt-swift fmt-lua fmt-nvim fmt-pi fmt-docs

fmt-go:
    just -f sdk/go/justfile fmt
    just -f cli/gty/justfile fmt

fmt-swift:
    just -f daemon/ghosttykitd/justfile fmt

fmt-lua:
    just -f sdk/lua/justfile fmt

fmt-pi:
    if [ -d pi/pi-paste/node_modules ]; then just -f pi/pi-paste/justfile fmt; else echo 'pi/pi-paste: skipping fmt; run just install-deps-pi'; fi

fmt-nvim:
    just -f nvim/justfile fmt

fmt-docs:
    if command -v prettier >/dev/null 2>&1; then prettier --write "**/*.md"; else echo 'docs: skipping prettier; install prettier'; fi
    if command -v markdownlint-cli2-fix >/dev/null 2>&1; then markdownlint-cli2-fix; else echo 'docs: skipping markdownlint fix; install markdownlint-cli2'; fi

# Lint all components.
lint: lint-go lint-swift lint-lua lint-nvim lint-pi lint-docs

lint-go:
    just -f sdk/go/justfile lint
    just -f cli/gty/justfile lint

lint-swift:
    just -f daemon/ghosttykitd/justfile lint

lint-lua:
    just -f sdk/lua/justfile lint

lint-pi:
    if [ -d pi/pi-paste/node_modules ]; then just -f pi/pi-paste/justfile lint; else echo 'pi/pi-paste: skipping lint; run just install-deps-pi'; fi

lint-nvim:
    just -f nvim/justfile lint

lint-docs:
    if command -v markdownlint-cli2 >/dev/null 2>&1; then markdownlint-cli2; else echo 'docs: skipping lint; install markdownlint-cli2'; fi

# Typecheck all components.
typecheck: typecheck-go typecheck-swift typecheck-lua typecheck-nvim typecheck-pi

typecheck-go:
    just -f sdk/go/justfile typecheck
    just -f cli/gty/justfile typecheck

typecheck-swift:
    just -f daemon/ghosttykitd/justfile typecheck

typecheck-lua:
    just -f sdk/lua/justfile typecheck

typecheck-pi:
    if [ -d pi/pi-paste/node_modules ]; then just -f pi/pi-paste/justfile typecheck; else echo 'pi/pi-paste: skipping typecheck; run just install-deps-pi'; fi

typecheck-nvim:
    just -f nvim/justfile typecheck

# Test all components with tests.
test: test-go test-swift test-lua test-nvim

test-go:
    just -f sdk/go/justfile test
    just -f cli/gty/justfile test

test-swift:
    just -f daemon/ghosttykitd/justfile test

test-lua:
    just -f sdk/lua/justfile test-all

test-nvim:
    just -f nvim/justfile test

# Build binaries and build-check non-binary packages.
build: build-go build-swift build-lua build-nvim build-pi

build-go:
    just -f cli/gty/justfile build

build-swift:
    just -f daemon/ghosttykitd/justfile build

build-lua:
    just -f sdk/lua/justfile build

build-pi:
    if [ -d pi/pi-paste/node_modules ]; then just -f pi/pi-paste/justfile build; else echo 'pi/pi-paste: skipping build; run just install-deps-pi'; fi

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

install-deps: install-deps-lua install-deps-nvim install-deps-pi

install-deps-lua:
    just -f sdk/lua/justfile install-deps

install-deps-nvim:
    just -f nvim/justfile install-deps

install-deps-pi:
    just -f pi/pi-paste/justfile install-deps

update-deps: update-deps-mise update-deps-go

update-deps-mise:
    mise upgrade --bump --local --exclude lua

update-deps-go:
    just -f sdk/go/justfile update-deps
    just -f cli/gty/justfile update-deps
