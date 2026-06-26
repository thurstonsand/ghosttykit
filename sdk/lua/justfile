set shell := ["bash", "-euo", "pipefail", "-c"]

rock_tree := "../../.luarocks"
luals_addons := "../../.luals/addons"
rockspec := "ghosttykit-scm-1.rockspec"
busted_luacats_rev := "5ed85d0e016a5eb5eca097aa52905eedf1b180f1"
luassert_luacats_rev := "d3528bb679302cbfdedefabb37064515ab95f7b9"

_default:
    just --list

install-deps:
    rm -rf {{rock_tree}}
    luarocks install --tree {{rock_tree}} --lua-version 5.1 --only-deps {{rockspec}}
    luarocks install --tree {{rock_tree}} --lua-version 5.1 busted
    luarocks install --tree {{rock_tree}} --lua-version 5.1 luacheck
    luarocks install --tree {{rock_tree}} --lua-version 5.1 nlua
    just -f {{justfile()}} install-luals-types

install-luals-types:
    rm -rf {{luals_addons}}/busted {{luals_addons}}/luassert
    mkdir -p {{luals_addons}}
    git clone https://github.com/LuaCATS/busted.git {{luals_addons}}/busted
    git -C {{luals_addons}}/busted checkout {{busted_luacats_rev}}
    git clone https://github.com/LuaCATS/luassert.git {{luals_addons}}/luassert
    git -C {{luals_addons}}/luassert checkout {{luassert_luacats_rev}}
    rm -f ../../.luals/nvim-runtime
    ln -s "$(nvim --headless -u NONE +'lua io.write(vim.env.VIMRUNTIME)' +q 2>&1)" ../../.luals/nvim-runtime

fmt:
    stylua --config-path stylua.toml lua spec

fmt-check:
    stylua --check --config-path stylua.toml lua spec

lint:
    eval "$(luarocks path --tree {{rock_tree}} --lua-version 5.1 --bin)" && luacheck lua spec

typecheck:
    lua-language-server --check=. --configpath=.luarc.json --checklevel=Warning

test:
    eval "$(luarocks path --tree {{rock_tree}} --lua-version 5.1 --bin)" && busted spec/protocol_spec.lua spec/error_spec.lua spec/socket_spec.lua spec/client_spec.lua spec/transport_luv_spec.lua

test-nvim:
    eval "$(luarocks path --tree {{rock_tree}} --lua-version 5.1 --bin)" && busted --run=nvim spec/transport_nvim_spec.lua

test-all: test test-nvim

build:
    luarocks make --tree {{rock_tree}} --lua-version 5.1 {{rockspec}}

check: fmt lint typecheck test-all build
