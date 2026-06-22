#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: $0 <package-dir> <install-recipe>" >&2
  exit 2
fi

package_dir="$1"
install_recipe="$2"
marker="${package_dir}/node_modules/.ghosttykit-deps.sha"

signature() {
  shasum "${package_dir}/package.json" "${package_dir}/package-lock.json" 2>/dev/null | shasum | awk '{print $1}'
}

current_signature="$(signature)"

if [ -d "${package_dir}/node_modules" ] && [ -f "${marker}" ] && [ "$(cat "${marker}")" = "${current_signature}" ]; then
  exit 0
fi

just "${install_recipe}"
mkdir -p "${package_dir}/node_modules"
signature > "${marker}"
