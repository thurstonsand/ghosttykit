#!/usr/bin/env bash
# Cuts a stable release from main: dates the Unreleased notes, sets the npm package versions, commits,
# tags, and pushes. The Release workflow publishes from the tag.
set -euo pipefail

version="${1:?usage: release.sh x.y.z}"

fail() {
  echo "release: $*" >&2
  exit 1
}

[[ "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "version must be x.y.z, got ${version}"

[[ "$(git symbolic-ref --quiet --short HEAD || true)" == "main" ]] || fail "not on main"
[[ -z "$(git status --porcelain)" ]] || fail "working tree is not clean"
git fetch --quiet origin main
head="$(git rev-parse HEAD)"
[[ "${head}" == "$(git rev-parse origin/main)" ]] || fail "main does not match origin/main"

runs="$(gh run list --commit "${head}" --json workflowName,status,conclusion \
  --jq '.[] | "\(.workflowName): \(if .status == "completed" then .conclusion else .status end)"')"
[[ -n "${runs}" ]] || fail "no CI runs for ${head}"
if grep -v -E ': success$' <<<"${runs}" >/dev/null; then
  fail "CI on ${head} is not green:"$'\n'"${runs}"
fi

current="$(scripts/check-release-notes.sh)"
newest="$(printf '%s\n%s\n' "${current}" "${version}" | sort -t . -k 1,1n -k 2,2n -k 3,3n | tail -n 1)"
[[ "${version}" != "${current}" && "${newest}" == "${version}" ]] ||
  fail "${version} is not greater than the current release ${current}"

unreleased="$(awk '
  $0 == "## [Unreleased]" { capture = 1; next }
  capture && /^## / { exit }
  capture && NF { print }
' RELEASE.md)"
[[ -n "${unreleased}" ]] || fail "the [Unreleased] section of RELEASE.md is empty"

notes="$(mktemp)"
trap 'rm -f "${notes}"' EXIT

awk -v version="${version}" -v date="$(date +%F)" '
  { print }
  $0 == "## [Unreleased]" { print ""; print "## [" version "] - " date }
' RELEASE.md >"${notes}"
cp "${notes}" RELEASE.md

npm --prefix sdk/ts version "${version}" --no-git-tag-version --ignore-scripts >/dev/null
npm --prefix pi/pi-paste version "${version}" --no-git-tag-version --ignore-scripts >/dev/null
# Pi paste's lockfile records the version of the SDK it links from sdk/ts.
npm --prefix pi/pi-paste install --package-lock-only --ignore-scripts --no-audit --no-fund >/dev/null

[[ "$(scripts/check-release-notes.sh)" == "${version}" ]] || fail "RELEASE.md and the package versions disagree"

git add RELEASE.md sdk/ts/package.json sdk/ts/package-lock.json pi/pi-paste/package.json pi/pi-paste/package-lock.json
git commit --quiet -m "chore(release): ${version}"

scripts/extract-release-notes.sh "v${version}" >"${notes}"
git tag -a "v${version}" --cleanup=verbatim -F "${notes}"

git push --atomic origin main "v${version}"
echo "Pushed main and v${version}. The Release workflow publishes it."
