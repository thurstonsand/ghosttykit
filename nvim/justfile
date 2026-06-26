set shell := ["bash", "-euo", "pipefail", "-c"]

rock_tree := "../.luarocks"
sdk_just := "../sdk/lua/justfile"
rockspec := "ghosttykit.nvim-scm-1.rockspec"

_default:
    just --list

install-deps:
    just -f {{sdk_just}} install-deps
    just -f {{justfile()}} install-deps-plugin

install-deps-plugin:
    just -f {{sdk_just}} build
    luarocks install --tree {{rock_tree}} --lua-version 5.1 --only-deps {{rockspec}}

fmt:
    stylua --config-path stylua.toml lua plugin spec lazy.lua

fmt-check:
    stylua --check --config-path stylua.toml lua plugin spec lazy.lua

lint:
    eval "$(luarocks path --tree {{rock_tree}} --lua-version 5.1 --bin)" && luacheck lua plugin spec lazy.lua

typecheck:
    lua-language-server --check=. --configpath=.luarc.json --checklevel=Warning

test:
    eval "$(luarocks path --tree {{rock_tree}} --lua-version 5.1 --bin)" && busted

build:
    just -f {{sdk_just}} build
    luarocks make --tree {{rock_tree}} --lua-version 5.1 {{rockspec}}

check: fmt lint typecheck test build
