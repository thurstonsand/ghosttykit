import { client, Paste, type SavedPasteFile } from "@thurstonsand/ghosttykit";

export async function receivePaste(outputDir: string): Promise<{
  editorText: string;
  notification?: string;
}> {
  const paste = await client().paste();
  return Paste.match(paste, {
    text: async (paste) => ({ editorText: await paste.text() }),
    files: async (paste) => {
      const files = await paste.save(outputDir);
      return {
        editorText: files.map((file) => `@${file.path}`).join(" "),
        notification: fileNotification(files),
      };
    },
  });
}

function fileNotification(files: readonly SavedPasteFile[]): string | undefined {
  const count = files.length;
  const totalBytes = files.reduce((sum, file) => sum + file.byteLength, 0);
  const mediaTypes = new Set(files.map((file) => file.mediaType).filter(Boolean));
  const parts = [`Pasted ${count} ${count === 1 ? "file" : "files"}`];

  if (mediaTypes.size === 1) {
    parts.push([...mediaTypes][0] ?? "");
  }
  if (totalBytes > 0) {
    parts.push(formatBytes(totalBytes));
  }

  return parts.filter(Boolean).join(" · ");
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
