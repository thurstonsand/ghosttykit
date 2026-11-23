import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const changelog = fileURLToPath(new URL("../../RELEASE.md", import.meta.url));
const expected = Array.from(
  readFileSync(changelog, "utf8").matchAll(/^## \[(\d+\.\d+\.\d+)\]/gm),
  ([, version]) => version,
);

// Pi does not export its reader; this check uses the installed dev dependency, never the host.
const { parseChangelog } = await import(
  new URL("./utils/changelog.js", import.meta.resolve("@earendil-works/pi-coding-agent"))
);
const parsed = parseChangelog(changelog).map(
  ({ major, minor, patch }) => `${major}.${minor}.${patch}`,
);
assert.deepEqual(parsed, expected, "Pi must recognize every released version in RELEASE.md");
console.log(`Pi recognized all ${parsed.length} release notes entries`);
