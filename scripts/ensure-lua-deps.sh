#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 3 ]; then
  echo "usage: $0 <marker-path> <install-recipe> <input> [<input> ...]" >&2
  exit 2
fi

marker="$1"
install_recipe="$2"
shift 2

signature() {
  shasum "$@" 2>/dev/null | shasum | awk '{print $1}'
}

current_signature="$(signature "$@")"

if [ -f "${marker}" ] && [ "$(cat "${marker}")" = "${current_signature}" ]; then
  exit 0
fi

just "${install_recipe}"
mkdir -p "$(dirname "${marker}")"
signature "$@" > "${marker}"
