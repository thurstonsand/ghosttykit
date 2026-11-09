# Release

GhosttyKit publishes release artifacts from GitHub Actions.

Pushes to `main` publish nightly artifacts. Pushes of `v*` tags publish stable artifacts. The release workflows keep stable tags immutable for package consumers and publish each binary nightly as its own prerelease.

## Release channels

### GitHub releases

The `Release` workflow builds a Darwin archive for Apple Silicon, and Linux archives for `amd64` and `arm64`. Intel Macs are not supported; the Homebrew formula refuses to install on one. Darwin archives carry `gty` and the signed, notarized `GhosttyKitD.app`; Linux archives carry `gty` alone, since the daemon is macOS-only. Every archive stamps its own release tag into `gty` so a `gty ssh` bootstrap can download the matching remote asset.

Pushes to `main` create a prerelease named `nightly-<next-patch>-dev-<github-run-id>-<short-sha>`, where `<next-patch>` is the newest release in `RELEASE.md` with its patch component incremented. Nightly archive versions use `<next-patch>-dev-<github-run-id>-<short-sha>` so package managers can reliably detect newer builds, and so a nightly always sorts above the stable release it was built on top of. Each nightly gets its own release tag, so Homebrew formula URLs remain stable even after later nightlies publish.

Stable releases are tag-driven, and `mise run release X.Y.Z` cuts one. It refuses unless `main` is checked out, clean, level with `origin/main`, and green in CI, and unless `## [Unreleased]` has entries and `X.Y.Z` is greater than the current release. It then moves the Unreleased entries under `## [X.Y.Z] - <today>`, sets both npm packages to `X.Y.Z`, commits `chore(release): X.Y.Z`, creates the annotated tag `vX.Y.Z` with that section as its body, and pushes `main` and the tag together. The workflow fails unless the tag, the npm package versions, and the newest `RELEASE.md` release agree, then creates the GitHub release with that `RELEASE.md` entry as the release body.

Versions follow semantic versioning: a release with any new feature (an `Added` entry), a raised floor (a higher minimum Pi, Node, OS, or other dependency version), or anything breaking is at least minor, and breaking is major from 1.0 on; patch is only for fixes and dependency updates.

The daemon's bundle version and the Homebrew formula version have no checked-in source: the workflow stamps the release version into them when it builds the archives and writes the formula.

### Release notes

`RELEASE.md` is the changelog for the whole monorepo, since every package versions in lockstep. Its sections are `## [Unreleased]` followed by `## [x.y.z] - YYYY-MM-DD`, newest first. `mise run release:lint`, part of `mise run check` and CI, fails if any other `##` heading appears, if releases do not strictly descend, or if the newest release is not the version in the npm packages' `package.json`.

### Homebrew tap

The `Release` workflow also updates the shared `thurstonsand/homebrew-tap` after publishing GitHub release archives.

Pushes to `main` update `Formula/ghosttykit-nightly.rb` to point at the newest nightly prerelease. Pushes of `v*` tags update `Formula/ghosttykit.rb`. The Homebrew formula version matches the GitHub release archive version. Both formulas install `gty` on macOS and Linux, and the daemon plus its `brew services` definition on macOS only.

### Lua SDK and Neovim plugin mirrors

The `Release` workflow splits monorepo subdirectories into standalone repositories:

| Monorepo path | Mirror repo                    |
| ------------- | ------------------------------ |
| `sdk/lua`     | `thurstonsand/ghosttykit.lua`  |
| `nvim`        | `thurstonsand/ghosttykit.nvim` |

Every push to `main` force-pushes each mirror repo's `main` branch and force-updates its `nightly` tag. Pushes of `v*` tags push matching stable mirror tags without force so an already-published stable package version cannot be replaced.

The Neovim plugin does not publish separate binary nightly artifacts. Pair the Homebrew `ghosttykit-nightly` formula with the `ghosttykit.nvim` mirror's `main` branch.

Local development and dogfooding can track mirror `main` instead.

### Go module

Go packages live in the root module `github.com/thurstonsand/ghosttykit`. Stable `v*` tags make both the SDK packages and CLI installable through normal Go module resolution, for example:

```sh
go get github.com/thurstonsand/ghosttykit/sdk/go@vX.Y.Z
go install github.com/thurstonsand/ghosttykit/cli/gty@vX.Y.Z
```

There is no separate Go registry publish step.

### npm packages

The `Release` workflow publishes the TypeScript SDK from `sdk/ts` as `@thurstonsand/ghosttykit` and the Pi extension from `pi/pi-paste` as `@thurstonsand/pi-paste`. It uses npm Trusted Publishing through GitHub Actions OIDC, so the repository does not store an npm token.

The package versions on `main` are the current release. Stable `v*` tags publish them as checked in, on the default `latest` dist-tag. Pushes to `main` publish unique prerelease versions like `X.Y.Z-nightly.<run-id>.<attempt>.<short-sha>` on the `nightly` dist-tag, where `X.Y.Z` is the current release with its patch component incremented, leaving `latest` untouched.

Pi paste packs `RELEASE.md` as its `CHANGELOG.md`, so Pi shows the release notes when it updates the extension.

The workflow runs shared CI once, publishes the TypeScript SDK first, then rewrites Pi paste's `@thurstonsand/ghosttykit` dependency to the exact SDK version from the same run before packing and publishing Pi paste. This keeps stable and nightly Pi paste packages paired with the matching SDK package.

## Repository secrets

### Package publishing

The release workflows use these package-publishing secrets:

| Secret                     | Purpose                                                                                           |
| -------------------------- | ------------------------------------------------------------------------------------------------- |
| `HOMEBREW_TAP_PRIVATE_KEY` | Writes Homebrew formulae to `thurstonsand/homebrew-tap`                                           |
| `HOMEBREW_TAP_TOKEN`       | Writes Lua mirror branches and tags to separate GitHub repositories                               |
| `LUAROCKS_API_KEY`         | Publishes the Lua SDK from `thurstonsand/ghosttykit.lua` to LuaRocks after stable SDK mirror tags |

`HOMEBREW_TAP_PRIVATE_KEY` is a repository-scoped deploy key whose public key has write access only to `thurstonsand/homebrew-tap`. `HOMEBREW_TAP_TOKEN` must have write access to:

- `thurstonsand/ghosttykit.lua`
- `thurstonsand/ghosttykit.nvim`

## Developer ID signing and notarization

Release archives must be signed with a Developer ID Application certificate and submitted to Apple notarization before publication. Repo is configured with the following to assist with that:

| Secret                                    | Purpose                                                                                  |
| ----------------------------------------- | ---------------------------------------------------------------------------------------- |
| `APPLE_CODESIGN_IDENTITY`                 | Exact codesign identity, for example `Developer ID Application: Name (TEAMID)`           |
| `APPLE_DEVELOPER_ID_CERTIFICATE_BASE64`   | Base64-encoded `.p12` export of the Developer ID Application certificate and private key |
| `APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD` | Password for the `.p12` export                                                           |
| `APPLE_NOTARY_KEY`                        | App Store Connect API key `.p8` contents                                                 |
| `APPLE_NOTARY_KEY_ID`                     | App Store Connect API key id                                                             |
| `APPLE_NOTARY_ISSUER_ID`                  | App Store Connect issuer id                                                              |

Created the certificate in Apple Developer under **Certificates, Identifiers & Profiles** using **Developer ID Application**. Exported it from Keychain Access as a password-protected `.p12`, then encode it:

```sh
base64 -i developer-id-application.p12 | pbcopy
```

Create the notarization API key in App Store Connect under **Users and Access > Integrations > App Store Connect API**.

The release workflow uses `apple-actions/import-codesign-certs` to import the certificate, signs `gty` and the bundled `GhosttyKitD.app`, packages them into a zip archive, submits the archive to `notarytool`, and uploads the notarized archive plus a SHA-256 sidecar. `GhosttyKitD.app` is a background-only app bundle around the SwiftPM-built `ghosttykitd` executable; Homebrew launches the daemon from inside that bundle so macOS TCC records Apple Events authorization against the stable bundle identifier instead of a versioned Cellar path. Release signing applies the Apple Events hardened-runtime entitlement to the daemon bundle.
