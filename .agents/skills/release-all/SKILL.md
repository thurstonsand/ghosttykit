---
name: release-all
description: Coordinates GhosttyKit releases across GitHub archives, Homebrew formulas, Lua mirrors, and LuaRocks. Use when preparing, tagging, publishing, or verifying a GhosttyKit release.
---

# Release All

Use this skill when preparing or publishing a GhosttyKit release.

## Release model

- Release from `main`.
- Push `main` before creating a stable tag so nightly artifacts publish first.
- Assume the release starts from a stable committed state. Do not repeat verification the user already performed.
- Do not push the stable tag until the user explicitly approves stable publishing.
- Use `RELEASE.md` for human release notes.
- Use the exact same release-note text from `RELEASE.md` for the annotated git tag body.
- Stable releases are `vX.Y.Z` tags.
- Stable package tags are immutable. Never force-push a stable release tag or stable mirror tag.
- Binary nightly releases are unique prereleases named `nightly-<version>`. Mirror nightly refs move with `main` and may be force-updated by automation.

## Release channels

One stable tag fans out into several release surfaces:

| Surface                 | Source workflow                                        | Result                                                         |
| ----------------------- | ------------------------------------------------------ | -------------------------------------------------------------- |
| GitHub release archives | `.github/workflows/release.yml`                        | Signed/notarized Darwin archives on `vX.Y.Z` or `nightly-*`    |
| Homebrew tap            | `.github/workflows/release.yml`                        | `thurstonsand/homebrew-ghosttykit/Formula/ghosttykit.rb`       |
| Lua SDK mirror          | `.github/workflows/publish-lua.yml`                    | `thurstonsand/ghosttykit.lua` `main`, `nightly`, and `vX.Y.Z`  |
| Neovim plugin mirror    | `.github/workflows/publish-lua.yml`                    | `thurstonsand/ghosttykit.nvim` `main`, `nightly`, and `vX.Y.Z` |
| Lua SDK LuaRock         | `sdk/lua/.github/workflows/luarocks.yml` in the mirror | `ghosttykit` on LuaRocks                                       |
| Pi paste npm package    | manual npm publish from `pi/pi-paste`                  | `@thurstonsand/pi-paste` on npm                                |

The SDK rock is part of the default release path because it is a library dependency. Neovim plugin releases are Git-based through the `ghosttykit.nvim` mirror. The Pi paste package is published manually to npm during stable releases only; do not publish npm nightlies unless the user explicitly asks for an npm prerelease flow.

## 1. Inspect release state

Check the current state before touching anything:

```sh
git status --short
git log --oneline --decorate -10
git tag --list 'v*' --sort=-version:refname | head -10
gh run list --branch main --limit 10
```

If the working tree has unrelated changes, leave them alone. If release-relevant changes are uncommitted, ask whether they belong in the release before proceeding.

Inspect changes since the latest stable tag:

```sh
LATEST_TAG="$(git describe --tags --abbrev=0 --match 'v[0-9]*')"
git diff --stat "${LATEST_TAG}..HEAD"
git log --oneline "${LATEST_TAG}..HEAD"
```

Summarize:

- user-facing features and fixes
- install, packaging, or release workflow changes
- SDK/plugin/API changes
- documentation updates
- likely semver bump: patch, minor, or major

Ask the user to confirm the target version unless they already specified it.

## 2. Prepare release notes

Update `RELEASE.md` with a new top entry:

```md
## X.Y.Z

Short release summary.

### Added

- User-facing change.

### Changed

- Packaging or install change.

### Fixed

- User-facing fix.
```

Omit empty sections. Do not list every internal refactor. If the user edits the notes, preserve their wording.

If release mechanics changed, update `docs/release.md` too.

## 3. Prepare Pi paste npm package when included

If `pi/pi-paste` has release-relevant changes, prepare its npm package before committing release prep.

Bump the package version with npm's version writer, but do not let npm create a commit or tag:

```sh
cd pi/pi-paste
npm version <patch|minor|major|X.Y.Z> --no-git-tag-version
npm run check
cd ../..
```

For an explicit version such as `0.3.0`, this is also valid:

```sh
cd pi/pi-paste
npm version 0.3.0 --no-git-tag-version
npm run check
cd ../..
```

This should update `pi/pi-paste/package.json` and `pi/pi-paste/package-lock.json`. If the Pi paste package is not part of the release, do not bump it.

## 4. Commit release prep

Stage only release-relevant files and commit. Do not stage unrelated user or agent work.

## 5. Push main and verify nightly artifacts

Push `main` first:

```sh
git push origin main
```

Watch both monorepo workflows for the pushed commit:

```sh
gh run list --branch main --limit 6
gh run watch <publish-lua-run-id> --exit-status
gh run watch <release-run-id> --exit-status
```

Verify nightly state:

```sh
HEAD_SHA="$(git rev-parse HEAD)"
gh release view nightly --json tagName,targetCommitish,isPrerelease,url
git ls-remote https://github.com/thurstonsand/ghosttykit.lua.git refs/heads/main refs/tags/nightly
git ls-remote https://github.com/thurstonsand/ghosttykit.nvim.git refs/heads/main refs/tags/nightly
```

For binary nightlies, find the newest `nightly-*` prerelease instead of the legacy moving `nightly` release:

```sh
gh release list --exclude-drafts --limit 10 | rg '^nightly-'
```

If the release needs hand-testing, stop here and ask the user to test before tagging.

## 6. Publish Pi paste to npm when included

If `pi/pi-paste` was version-bumped for this stable release, publish it before creating the stable git tag.

Confirm npm identity and package contents:

```sh
cd pi/pi-paste
npm whoami
npm publish --dry-run
```

Read the tarball contents. Make sure expected source files are included and obvious junk is absent.

Ask the user to run the real publish:

```sh
npm publish
```

After publish, verify npm sees the new version:

```sh
npm view @thurstonsand/pi-paste version dist-tags --json
cd ../..
```

Do not create the stable git tag until this verification shows the npm package is live. If npm publish fails, stop and report the blocker; do not tag a release whose npm package version has not published.

## 7. Create and push the stable tag

Create an annotated tag after the user approves stable publishing. Use the exact final `RELEASE.md` entry for that version as the tag notes.

```sh
VERSION=X.Y.Z
scripts/extract-release-notes.sh "v${VERSION}" > "/tmp/ghosttykit-v${VERSION}-notes.md"
git tag -a "v${VERSION}" --cleanup=verbatim -F "/tmp/ghosttykit-v${VERSION}-notes.md"
git push origin "v${VERSION}"
```

Do not force-push a stable tag. If a tag already exists, stop and inspect; do not overwrite it.

## 8. Watch stable monorepo publishing

The stable tag should trigger both monorepo workflows:

```sh
gh run list --limit 10 --json databaseId,workflowName,headBranch,headSha,status,conclusion,event
gh run watch <publish-lua-run-id> --exit-status
gh run watch <release-run-id> --exit-status
```

`Publish Lua Mirrors` should push stable mirror tags without force. If it fails because a stable mirror tag already exists, treat that as a real release immutability violation and stop.

`Release` should create the GitHub release archives using the `RELEASE.md` entry as the release body, then update the stable Homebrew formula.

## 9. Watch LuaRocks publishing

After the stable mirror tags exist, verify or watch the SDK LuaRocks workflow in the `ghosttykit.lua` mirror repo.

The SDK mirror has a tag-triggered LuaRocks workflow:

```sh
gh run list -R thurstonsand/ghosttykit.lua --limit 10
gh run watch -R thurstonsand/ghosttykit.lua <run-id> --exit-status
```

## 10. Final verification

Verify release surfaces that were not already checked while watching workflows.

```sh
VERSION=X.Y.Z

git status --short
git ls-remote --tags origin "v${VERSION}"

gh release view "v${VERSION}" --json tagName,isDraft,isPrerelease,publishedAt,url
gh release list --exclude-drafts --limit 10 | rg '^nightly-'

git ls-remote https://github.com/thurstonsand/ghosttykit.lua.git refs/heads/main "refs/tags/v${VERSION}" refs/tags/nightly
git ls-remote https://github.com/thurstonsand/ghosttykit.nvim.git refs/heads/main "refs/tags/v${VERSION}" refs/tags/nightly

gh api repos/thurstonsand/homebrew-ghosttykit/contents/Formula/ghosttykit.rb --jq .download_url
luarocks search ghosttykit
npm view @thurstonsand/pi-paste version dist-tags --json
```

For Homebrew, inspect the formula if needed:

```sh
tmpdir="$(mktemp -d)"
git clone --depth 1 https://github.com/thurstonsand/homebrew-ghosttykit.git "${tmpdir}/tap"
sed -n '1,220p' "${tmpdir}/tap/Formula/ghosttykit.rb"
rm -rf "${tmpdir}"
```

## Final report

Report:

- version released
- release commit hash and tag
- GitHub release URL
- Homebrew formula status
- Lua mirror tags and LuaRocks status
- Pi paste npm package status, if included
- workflows watched and whether they passed
- any manual test evidence from the user
- any follow-up work, such as improving this skill after the release
