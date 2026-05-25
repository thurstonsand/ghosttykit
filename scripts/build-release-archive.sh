#!/usr/bin/env bash
set -euo pipefail

version="${RELEASE_VERSION:-$(git describe --tags --always --dirty)}"
goos="$(go env GOOS)"
goarch="$(go env GOARCH)"
name="ghosttykit_${version}_${goos}_${goarch}"
root="dist/${name}"
archive="dist/${name}.zip"

rm -rf dist
mkdir -p "${root}/bin"

go build \
  -C cli/gty \
  -trimpath \
  -ldflags "-s -w -X github.com/thurstonsand/ghosttykit/sdk/go.Version=${version}" \
  -o "../../${root}/bin/gty" \
  .

swift build --package-path daemon/ghosttykitd --disable-sandbox -c release
cp daemon/ghosttykitd/.build/release/ghosttykitd "${root}/bin/ghosttykitd"

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  codesign --force --timestamp --options runtime --sign "${CODESIGN_IDENTITY}" "${root}/bin/gty"
  codesign --force --timestamp --options runtime --sign "${CODESIGN_IDENTITY}" "${root}/bin/ghosttykitd"
fi

cp README.md LICENSE* "${root}/" 2>/dev/null || true

ditto -c -k --sequesterRsrc --keepParent "${root}" "${archive}"

if [[ -n "${APPLE_NOTARY_KEY_PATH:-}" && -n "${APPLE_NOTARY_KEY_ID:-}" && -n "${APPLE_NOTARY_ISSUER_ID:-}" ]]; then
  xcrun notarytool submit "${archive}" \
    --key "${APPLE_NOTARY_KEY_PATH}" \
    --key-id "${APPLE_NOTARY_KEY_ID}" \
    --issuer "${APPLE_NOTARY_ISSUER_ID}" \
    --wait
fi

shasum -a 256 "${archive}" > "${archive}.sha256"
rm -rf "${root}"
