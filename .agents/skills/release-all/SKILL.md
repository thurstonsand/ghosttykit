---
name: release-all
description: Coordinates GhosttyKit releases across GitHub archives, Homebrew formulas, Lua mirrors, and LuaRocks. Use when preparing, tagging, publishing, or verifying a GhosttyKit release.
---

# Release All

Use this skill when preparing or publishing a GhosttyKit release.

## Release model

- Release from `main` with `mise run release X.Y.Z`. It refuses unless `main` is clean, level with `origin/main`, and green in CI, then dates the `## [Unreleased]` notes, writes the version into both npm packages, commits `chore(release): X.Y.Z`, creates the annotated `vX.Y.Z` tag from that section, and pushes `main` and the tag together.
- Assume the release starts from a stable committed state. Do not repeat verification the user already performed.
- Do not run the release task until the user explicitly approves stable publishing.
- Use `RELEASE.md` for human release notes: `## [Unreleased]`, then `## [X.Y.Z] - YYYY-MM-DD` sections, newest first.
- The package versions on `main` are the current release. Nightlies compute their own versions from it.
- Stable releases are `vX.Y.Z` tags.
- Stable package tags are immutable. Never force-push a stable release tag or stable mirror tag.
- Binary nightly releases are unique prereleases named `nightly-<version>`. Mirror nightly refs move with `main` and may be force-updated by automation.

## Release channels

One stable tag fans out into several release surfaces:

| Surface                    | Source workflow                                        | Result                                                         |
| -------------------------- | ------------------------------------------------------ | -------------------------------------------------------------- |
| GitHub release archives    | `.github/workflows/release.yml`                        | Signed/notarized Darwin archives on `vX.Y.Z` or `nightly-*`    |
| Homebrew tap               | `.github/workflows/release.yml` → tap `Formulae` audit | `thurstonsand/homebrew-tap/Formula/ghosttykit.rb`              |
| Lua SDK mirror             | `.github/workflows/release.yml`                        | `thurstonsand/ghosttykit.lua` `main`, `nightly`, and `vX.Y.Z`  |
| Neovim plugin mirror       | `.github/workflows/release.yml`                        | `thurstonsand/ghosttykit.nvim` `main`, `nightly`, and `vX.Y.Z` |
| Lua SDK LuaRock            | `sdk/lua/.github/workflows/luarocks.yml` in the mirror | `ghosttykit` on LuaRocks                                       |
| TypeScript SDK npm package | `.github/workflows/release.yml`                        | `@thurstonsand/ghosttykit` on npm                              |
| Pi paste npm package       | `.github/workflows/release.yml`                        | `@thurstonsand/pi-paste` on npm                                |

The SDK rock is part of the default release path because it is a library dependency. Neovim plugin releases are Git-based through the `ghosttykit.nvim` mirror. npm packages publish automatically for both stable and nightly releases. The TypeScript SDK publishes before Pi paste; the workflow rewrites Pi paste's SDK dependency to the exact SDK version published by the same run.

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
- likely bump: patch, minor, or major, by the versioning rule in `docs/release.md`

Ask the user to confirm the target version unless they already specified it.

## 2. Prepare release notes

Review the entries under `## [Unreleased]` in `RELEASE.md` against the changes since the latest tag, and fill in what is missing:

```md
## [Unreleased]

Short release summary.

### Added

- User-facing change.

### Changed

- Packaging or install change.

### Fixed

- User-facing fix.
```

Omit empty sections. Do not list every internal refactor. If the user edits the notes, preserve their wording. Leave the heading as `## [Unreleased]`; the release task dates it.

If release mechanics changed, update `docs/release.md` too.

## 3. Prepare npm packages when included

Leave the npm package versions alone: the release task writes them. If `sdk/ts` or `pi/pi-paste` has release-relevant changes, verify the package before committing release prep:

```sh
mise run //sdk/ts:check
mise run //pi/pi-paste:check
```

Do not manually bump the dependency during release prep. The publish workflow rewrites it to the exact SDK version from the same stable or nightly run before packing Pi paste.

## 4. Commit release prep

Stage only release-relevant files and commit. Do not stage unrelated user or agent work.

## 5. Push main and verify nightly artifacts

The release task refuses to run until CI on `main`'s head is green, so push the release prep first:

```sh
git push origin main
```

Watch the monorepo release workflow for the pushed commit:

```sh
gh run list --workflow Release --branch main --limit 6
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

The monorepo workflow pushes the generated nightly formula to `thurstonsand/homebrew-tap`, which triggers a separate `Formulae` workflow. The release workflow does not wait for that downstream audit. Find the run for the exact generated tap commit and watch it too:

```sh
tap_sha=$(gh api "repos/thurstonsand/homebrew-tap/commits?path=Formula/ghosttykit-nightly.rb&per_page=1" --jq '.[0].sha')
tap_run_id=$(gh run list -R thurstonsand/homebrew-tap --workflow Formulae --commit "${tap_sha}" --limit 1 --json databaseId --jq '.[0].databaseId')
gh run watch -R thurstonsand/homebrew-tap "${tap_run_id}" --exit-status
```

Do not report the nightly as published until both the monorepo release workflow and the downstream Homebrew formula workflow pass.

If the release needs hand-testing, stop here and ask the user to test before tagging.

## 6. Verify npm package nightlies when included

After pushing `main`, the `Release` workflow should publish the TypeScript SDK first and Pi paste second.

Watch the workflow:

```sh
gh run list --workflow Release --branch main --limit 5
gh run watch <release-run-id> --exit-status
```

Verify nightly npm dist-tags when the workflow completes:

```sh
npm view @thurstonsand/ghosttykit version dist-tags --json
npm view @thurstonsand/pi-paste version dist-tags --json
```

Inspect the packed Pi paste package or npm metadata to confirm its `@thurstonsand/ghosttykit` dependency points at the exact SDK version from the same run.

## 7. Cut the stable release

The npm publishes sign provenance through Sigstore, and a Rekor outage fails them after the tag is out. Before releasing, check that <https://status.sigstore.dev> reports every service online, and that Rekor answers:

```sh
curl -fsS https://rekor.sigstore.dev/api/v1/log | jq '{treeSize, rootHash}'
```

After the user approves stable publishing, cut the release:

```sh
mise run release X.Y.Z
```

The task commits, tags, and pushes `main` and `vX.Y.Z`. Do not force-push a stable tag. If a tag already exists, stop and inspect; do not overwrite it.

## 8. Watch stable monorepo publishing

The stable tag should trigger the monorepo release workflow:

```sh
gh run list --workflow Release --limit 10 --json databaseId,workflowName,headBranch,headSha,status,conclusion,event
gh run watch <release-run-id> --exit-status
```

`Release` fails fast unless the tag, both npm package versions, and the newest `RELEASE.md` release agree. It should push stable mirror tags without force. If it fails because a stable mirror tag already exists, treat that as a real release immutability violation and stop.

`Release` should create the GitHub release archives using the `RELEASE.md` entry as the release body, then update the stable Homebrew formula.

The formula push triggers the tap's separate `Formulae` workflow. Find the run for the exact generated tap commit and watch it through completion:

```sh
tap_sha=$(gh api "repos/thurstonsand/homebrew-tap/commits?path=Formula/ghosttykit.rb&per_page=1" --jq '.[0].sha')
tap_run_id=$(gh run list -R thurstonsand/homebrew-tap --workflow Formulae --commit "${tap_sha}" --limit 1 --json databaseId --jq '.[0].databaseId')
gh run watch -R thurstonsand/homebrew-tap "${tap_run_id}" --exit-status
```

Do not report the stable release as published until both the monorepo release workflow and the downstream Homebrew formula workflow pass.

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

gh api repos/thurstonsand/homebrew-tap/contents/Formula/ghosttykit.rb --jq .download_url
luarocks search ghosttykit
npm view @thurstonsand/ghosttykit version dist-tags --json
npm view @thurstonsand/pi-paste version dist-tags --json
```

For Homebrew, inspect the formula if needed:

```sh
tmpdir="$(mktemp -d)"
git clone --depth 1 https://github.com/thurstonsand/homebrew-tap.git "${tmpdir}/tap"
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
- TypeScript SDK and Pi paste npm package status, if included
- monorepo and exact-commit downstream Homebrew workflows watched and whether they passed
- any manual test evidence from the user
- any follow-up work, such as improving this skill after the release
