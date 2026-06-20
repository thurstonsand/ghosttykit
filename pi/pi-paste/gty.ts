import { type Static, Type } from "typebox";
import { parseTypeBoxValue } from "./typebox.js";

const PASTE_FILE_SCHEMA = Type.Object({
  path: Type.String(),
  fileName: Type.Optional(Type.String()),
  mediaType: Type.Optional(Type.String()),
  bytes: Type.Number(),
  source: Type.Optional(Type.String()),
});

const PASTE_RESULT_SCHEMA = Type.Union([
  Type.Object({
    kind: Type.Literal("text"),
    text: Type.String(),
  }),
  Type.Object({
    kind: Type.Literal("files"),
    files: Type.Array(PASTE_FILE_SCHEMA),
    bytes: Type.Optional(Type.Number()),
  }),
]);

export type PasteResult = Static<typeof PASTE_RESULT_SCHEMA>;

export interface ExecResult {
  stdout: string;
  stderr: string;
  code: number | null;
}

export async function runGtyPaste(
  exec: (command: string, args: string[]) => Promise<ExecResult>,
  gtyBin: string,
  outputDir: string,
): Promise<PasteResult> {
  const result = await exec(gtyBin, ["paste", "--output-dir", outputDir, "--json"]);
  if (result.code !== 0) {
    throw new Error(commandFailureMessage(result));
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(result.stdout);
  } catch (error) {
    throw new Error(`gty paste returned invalid JSON: ${String(error)}`);
  }

  return parseTypeBoxValue(PASTE_RESULT_SCHEMA, parsed, "Invalid gty paste response");
}

export function pasteEditorText(result: PasteResult): string {
  switch (result.kind) {
    case "text":
      return result.text;
    case "files":
      return result.files.map((file) => `@${file.path}`).join(" ");
  }
}

export function fileNotification(result: PasteResult): string | undefined {
  switch (result.kind) {
    case "text":
      return undefined;
    case "files": {
      const count = result.files.length;
      const totalBytes = result.files.reduce((sum, file) => sum + file.bytes, 0);
      const mediaTypes = new Set(result.files.map((file) => file.mediaType).filter(Boolean));
      const parts = [`Pasted ${count} ${count === 1 ? "file" : "files"}`];

      if (mediaTypes.size === 1) {
        parts.push([...mediaTypes][0] ?? "");
      }
      if (totalBytes > 0) {
        parts.push(formatBytes(totalBytes));
      }

      return parts.filter(Boolean).join(" · ");
    }
  }
}

function commandFailureMessage(result: ExecResult): string {
  const detail =
    result.stderr.trim() || result.stdout.trim() || `exit code ${result.code ?? "unknown"}`;
  return `gty paste failed: ${detail}`;
}

function formatBytes(bytes: number): string {
  const units = ["B", "KiB", "MiB", "GiB"];
  let value = bytes;
  let unitIndex = 0;

  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex += 1;
  }

  if (unitIndex === 0) {
    return `${bytes} B`;
  }

  return `${value.toFixed(value >= 10 ? 0 : 1)} ${units[unitIndex]}`;
}
