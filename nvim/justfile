set shell := ["bash", "-euo", "pipefail", "-c"]

lua_check := "if command -v luajit >/dev/null 2>&1; then checker=luajit; elif command -v lua >/dev/null 2>&1; then checker=lua; else echo 'nvim: skipping Lua syntax check; install lua or luajit'; exit 0; fi; while IFS= read -r -d '' path; do $checker -e 'assert(loadfile(arg[1]))' \"$path\"; done < <(find lua -name '*.lua' -print0)"

_default:
    just --list

fmt:
    if command -v stylua >/dev/null 2>&1; then stylua lua; else {{lua_check}}; fi

lint:
    {{lua_check}}

typecheck: lint

check: lint

build: lint
