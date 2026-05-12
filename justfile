set shell := ["bash", "-euo", "pipefail", "-c"]

_default:
    just --list

# Format all components.
fmt: fmt-go fmt-swift fmt-pi fmt-nvim

fmt-go:
    just -f sdk/go/justfile fmt
    just -f cli/gty/justfile fmt

fmt-swift:
    just -f daemon/ghosttykitd/justfile fmt

fmt-pi:
    if [ -d pi/pi-paste/node_modules ]; then just -f pi/pi-paste/justfile fmt; else echo 'pi/pi-paste: skipping fmt; run just install-deps-pi'; fi

fmt-nvim:
    just -f nvim/justfile fmt

# Lint all components.
lint: lint-go lint-swift lint-pi lint-nvim

lint-go:
    just -f sdk/go/justfile lint
    just -f cli/gty/justfile lint

lint-swift:
    just -f daemon/ghosttykitd/justfile lint

lint-pi:
    if [ -d pi/pi-paste/node_modules ]; then just -f pi/pi-paste/justfile lint; else echo 'pi/pi-paste: skipping lint; run just install-deps-pi'; fi

lint-nvim:
    just -f nvim/justfile lint

# Typecheck all components.
typecheck: typecheck-go typecheck-swift typecheck-pi typecheck-nvim

typecheck-go:
    just -f sdk/go/justfile typecheck
    just -f cli/gty/justfile typecheck

typecheck-swift:
    just -f daemon/ghosttykitd/justfile typecheck

typecheck-pi:
    if [ -d pi/pi-paste/node_modules ]; then just -f pi/pi-paste/justfile typecheck; else echo 'pi/pi-paste: skipping typecheck; run just install-deps-pi'; fi

typecheck-nvim:
    just -f nvim/justfile typecheck

# Test all components with tests.
test: test-go

test-go:
    just -f sdk/go/justfile test
    just -f cli/gty/justfile test

# Build binaries and build-check non-binary packages.
build: build-go build-swift build-pi build-nvim

build-go:
    just -f cli/gty/justfile build

build-swift:
    just -f daemon/ghosttykitd/justfile build

build-pi:
    if [ -d pi/pi-paste/node_modules ]; then just -f pi/pi-paste/justfile build; else echo 'pi/pi-paste: skipping build; run just install-deps-pi'; fi

build-nvim:
    just -f nvim/justfile build

# Run all checks.
check: fmt lint typecheck test build

install-deps: install-deps-pi

install-deps-pi:
    just -f pi/pi-paste/justfile install-deps

update-deps-go:
    just -f sdk/go/justfile update-deps
    just -f cli/gty/justfile update-deps
