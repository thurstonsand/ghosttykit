#!/usr/bin/env bash
# Validates RELEASE.md against the published package versions and prints the top released version.
set -euo pipefail

release_file="${1:-RELEASE.md}"
packages=(sdk/ts/package.json pi/pi-paste/package.json)

top_version="$(
  awk '
    /^## / {
      if ($0 == "## [Unreleased]") {
        if (released > 0 || unreleased) {
          printf "%s:%d: [Unreleased] must be the first section\n", FILENAME, FNR > "/dev/stderr"
          failed = 1
        }
        unreleased = 1
        next
      }

      if ($0 !~ /^## \[[0-9]+\.[0-9]+\.[0-9]+\] - [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) {
        printf "%s:%d: heading is neither \"## [Unreleased]\" nor \"## [x.y.z] - YYYY-MM-DD\": %s\n", FILENAME, FNR, $0 > "/dev/stderr"
        failed = 1
        next
      }

      version = substr($0, 5, index($0, "]") - 5)
      split(version, part, ".")
      if (released > 0 && !(part[1] < last[1] || (part[1] == last[1] && (part[2] < last[2] || (part[2] == last[2] && part[3] < last[3]))))) {
        printf "%s:%d: %s does not come after %s in descending order\n", FILENAME, FNR, version, last_version > "/dev/stderr"
        failed = 1
      }
      if (released == 0) {
        top = version
      }
      released++
      last[1] = part[1] + 0
      last[2] = part[2] + 0
      last[3] = part[3] + 0
      last_version = version
    }

    END {
      if (!unreleased) {
        printf "%s: missing \"## [Unreleased]\"\n", FILENAME > "/dev/stderr"
        failed = 1
      }
      if (released == 0) {
        printf "%s: no released version\n", FILENAME > "/dev/stderr"
        failed = 1
      }
      if (failed) {
        exit 1
      }
      print top
    }
  ' "${release_file}"
)"

for package in "${packages[@]}"; do
  package_version="$(jq -r .version "${package}")"
  if [[ "${package_version}" != "${top_version}" ]]; then
    echo "${package} is at ${package_version}, but the newest release in ${release_file} is ${top_version}" >&2
    exit 1
  fi
done

echo "${top_version}"
