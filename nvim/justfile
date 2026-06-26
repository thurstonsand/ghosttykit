set shell := ["bash", "-euo", "pipefail", "-c"]

rock_tree := "../.luarocks"
sdk_just := "../sdk/lua/justfile"
rockspec := "ghosttykit.nvim-scm-1.rockspec"
nvim_package_path := "lua/?.lua;lua/?/init.lua;../sdk/lua/lua/?.lua;../sdk/lua/lua/?/init.lua;spec/?.lua;"

_default:
    just --list

install-deps:
    just -f {{sdk_just}} install-deps
    just -f {{sdk_just}} build
    luarocks install --tree {{rock_tree}} --lua-version 5.1 --only-deps {{rockspec}}

fmt:
    stylua --config-path stylua.toml lua plugin spec lazy.lua

lint:
    eval "$(luarocks path --tree {{rock_tree}} --lua-version 5.1 --bin)" && luacheck lua plugin spec lazy.lua

typecheck:
    lua-language-server --check=. --configpath=.luarc.json --checklevel=Warning

test:
    eval "$(luarocks path --tree {{rock_tree}} --lua-version 5.1 --bin)" && nvim --headless -u NONE -c 'set rtp+=.' -c 'lua package.path = "{{nvim_package_path}}" .. package.path; arg = { "spec/config_spec.lua", "spec/keymaps_spec.lua", "spec/lazy_spec.lua", "spec/tty_spec.lua", "spec/navigation_spec.lua", "spec/autocmds_spec.lua" }; require("busted.runner")({ standalone = false })' -c qall

build:
    just -f {{sdk_just}} build
    luarocks make --tree {{rock_tree}} --lua-version 5.1 {{rockspec}}

check: fmt lint typecheck test build
