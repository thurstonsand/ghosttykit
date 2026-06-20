# Release

GhosttyKit publishes release artifacts from GitHub Actions.

Pushes to `main` publish nightly artifacts. Pushes of `v*` tags publish stable artifacts. The release workflows keep stable tags immutable for package consumers and publish each binary nightly as its own prerelease.

## Release channels

### GitHub releases

The `Release` workflow builds Darwin archives for Apple Silicon and Intel Macs.

Pushes to `main` create a prerelease named `nightly-<latest-tag>-dev-<github-run-id>-<short-sha>`. Nightly archive versions use `<latest-tag>-dev-<github-run-id>-<short-sha>` so package managers can reliably detect newer builds. Each nightly gets its own release tag, so Homebrew formula URLs remain stable even after later nightlies publish.

Stable releases are tag-driven. Create and push an annotated `v*` git tag; the workflow then creates the GitHub release with the `RELEASE.md` entry as the release body.

### Homebrew tap

The `Release` workflow also updates `thurstonsand/homebrew-ghosttykit` after publishing GitHub release archives.

Pushes to `main` update `Formula/ghosttykit-nightly.rb` to point at the newest nightly prerelease. Pushes of `v*` tags update `Formula/ghosttykit.rb`. The Homebrew formula version matches the GitHub release archive version.

### Lua SDK and Neovim plugin mirrors

The `Publish Lua Mirrors` workflow splits monorepo subdirectories into standalone repositories:

| Monorepo path | Mirror repo                    |
| ------------- | ------------------------------ |
| `sdk/lua`     | `thurstonsand/ghosttykit.lua`  |
| `nvim`        | `thurstonsand/ghosttykit.nvim` |

Every push to `main` force-pushes each mirror repo's `main` branch and force-updates its `nightly` tag. Pushes of `v*` tags push matching stable mirror tags without force so an already-published stable package version cannot be replaced.

Local development and dogfooding can track mirror `main` instead.

## Repository secrets

### Package publishing

The release workflows use these package-publishing secrets:

| Secret               | Purpose                                                                                           |
| -------------------- | ------------------------------------------------------------------------------------------------- |
| `HOMEBREW_TAP_TOKEN` | Writes Homebrew formulas and Lua mirror branches/tags to separate GitHub repositories             |
| `LUAROCKS_API_KEY`   | Publishes the Lua SDK from `thurstonsand/ghosttykit.lua` to LuaRocks after stable SDK mirror tags |

`HOMEBREW_TAP_TOKEN` must have write access to:

- `thurstonsand/homebrew-ghosttykit`
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
