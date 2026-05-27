# Release

GhosttyKit publishes release archives from GitHub Actions.

Pushes to `main` update the moving `nightly` prerelease. Pushes of `v*` tags create normal releases. Each release builds Darwin archives for Apple Silicon and Intel Macs.

## Developer ID signing and notarization

Release archives must be signed with a Developer ID Application certificate and submitted to Apple notarization before publication. Configure these repository secrets before enabling release pushes:

| Secret                                    | Purpose                                                                                  |
| ----------------------------------------- | ---------------------------------------------------------------------------------------- |
| `APPLE_CODESIGN_IDENTITY`                 | Exact codesign identity, for example `Developer ID Application: Name (TEAMID)`           |
| `APPLE_DEVELOPER_ID_CERTIFICATE_BASE64`   | Base64-encoded `.p12` export of the Developer ID Application certificate and private key |
| `APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD` | Password for the `.p12` export                                                           |
| `APPLE_NOTARY_KEY`                        | App Store Connect API key `.p8` contents                                                 |
| `APPLE_NOTARY_KEY_ID`                     | App Store Connect API key id                                                             |
| `APPLE_NOTARY_ISSUER_ID`                  | App Store Connect issuer id                                                              |

Create the certificate in Apple Developer under **Certificates, Identifiers & Profiles** using **Developer ID Application**. Export it from Keychain Access as a password-protected `.p12`, then encode it:

```sh
base64 -i developer-id-application.p12 | pbcopy
```

Create the notarization API key in App Store Connect under **Users and Access > Integrations > App Store Connect API**.

The release workflow uses `apple-actions/import-codesign-certs` to import the certificate, signs `gty` and `ghosttykitd`, packages them into a zip archive, submits the archive to `notarytool`, and uploads the notarized archive plus a SHA-256 sidecar. Standalone Mach-O command-line binaries can be notarized, but Apple does not support stapling tickets directly to them; use a signed installer package or disk image if a stapled distribution artifact is required.
