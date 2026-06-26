import { randomUUID } from "node:crypto";
import { once } from "node:events";
import { createWriteStream } from "node:fs";
import { mkdir, rm } from "node:fs/promises";
import path from "node:path";
import type { Readable, Writable } from "node:stream";
import { extension } from "mime-types";
import sanitize from "sanitize-filename";
import { InvalidReplyError, PasteConsumedError } from "./errors.js";
import type {
  FilesPaste,
  Paste,
  PasteFile,
  PasteFileContent,
  PasteState,
  SavedPasteFile,
  TextPaste,
} from "./paste.js";
import type { PasteFrameFile, PasteStreamHeader } from "./protocol.js";

export function pasteFromStream(
  header: PasteStreamHeader,
  body: Readable,
  close: () => void,
): Paste {
  const reader = new ExactStreamReader(body);
  switch (header.kind) {
    case "text":
      return new TextPasteImpl(header.bytes, reader, close);
    case "files":
      return new FilesPasteImpl(header.bytes, header.files.map(normalizePasteFile), reader, close);
  }
}

function normalizePasteFile(file: PasteFrameFile): PasteFile {
  assertValidByteCount(file.bytes, `clipboard file ${file.fileName ?? ""} has invalid byte count`);
  return {
    fileName: file.fileName,
    mediaType: file.mediaType,
    byteLength: file.bytes,
    source: file.source,
  };
}

class TextPasteImpl implements TextPaste {
  readonly kind = "text";
  #state: PasteState = "pending";

  constructor(
    readonly byteLength: number,
    private readonly reader: ExactStreamReader,
    private readonly closeStream: () => void,
  ) {
    assertValidByteCount(byteLength, "clipboard text has invalid byte count");
  }

  get state(): PasteState {
    return this.#state;
  }

  get consumed(): boolean {
    return this.#state === "consumed";
  }

  async text(): Promise<string> {
    return Buffer.from(await this.raw()).toString("utf8");
  }

  raw(): Promise<Uint8Array> {
    return this.consume(async () => this.reader.readBytes(this.byteLength));
  }

  save(outputDir: string): Promise<readonly SavedPasteFile[]> {
    return this.consume(async () => {
      const file: PasteFile = {
        mediaType: "text/plain",
        byteLength: this.byteLength,
        source: "pasteboard-text",
      };
      const saved = await saveFile(this.reader, file, outputDir, uniqueTextFileName());
      return [saved];
    });
  }

  private async consume<T>(operation: () => Promise<T>): Promise<T> {
    claimPending(this.#state);
    this.#state = "consuming";
    try {
      return await operation();
    } finally {
      this.#state = "consumed";
      this.closeStream();
    }
  }
}

class FilesPasteImpl implements FilesPaste {
  readonly kind = "files";
  #state: PasteState = "pending";

  constructor(
    readonly byteLength: number,
    readonly files: readonly PasteFile[],
    private readonly reader: ExactStreamReader,
    private readonly closeStream: () => void,
  ) {
    assertValidByteCount(byteLength, "clipboard files have invalid byte count");
  }

  get state(): PasteState {
    return this.#state;
  }

  get consumed(): boolean {
    return this.#state === "consumed";
  }

  contents(): Promise<readonly PasteFileContent[]> {
    return this.consume(async () => {
      const contents: PasteFileContent[] = [];
      for (const file of this.files) {
        contents.push({ ...file, data: await this.reader.readBytes(file.byteLength) });
      }
      return contents;
    });
  }

  save(outputDir: string): Promise<readonly SavedPasteFile[]> {
    return this.consume(async () => {
      const savedFiles: SavedPasteFile[] = [];
      for (const file of this.files) {
        savedFiles.push(await saveFile(this.reader, file, outputDir, uniqueFileName(file)));
      }
      return savedFiles;
    });
  }

  private async consume<T>(operation: () => Promise<T>): Promise<T> {
    claimPending(this.#state);
    this.#state = "consuming";
    try {
      return await operation();
    } finally {
      this.#state = "consumed";
      this.closeStream();
    }
  }
}

function claimPending(state: PasteState): void {
  if (state !== "pending") {
    throw new PasteConsumedError("paste stream has already been consumed");
  }
}

async function saveFile(
  reader: ExactStreamReader,
  file: PasteFile,
  outputDir: string,
  fileName: string,
): Promise<SavedPasteFile> {
  assertValidByteCount(
    file.byteLength,
    `clipboard file ${file.fileName ?? ""} has invalid byte count`,
  );
  await mkdir(outputDir, { recursive: true, mode: 0o700 });

  const filePath = path.join(outputDir, fileName);
  const stream = createWriteStream(filePath, { flags: "wx", mode: 0o600 });
  let removeFile = true;

  try {
    await reader.writeTo(stream, file.byteLength);
    await closeWritable(stream);
    removeFile = false;
    return { ...file, path: filePath };
  } catch (error) {
    stream.destroy();
    if (removeFile) {
      await rm(filePath, { force: true }).catch(() => undefined);
    }
    throw error;
  }
}

function uniqueTextFileName(): string {
  return `pasted-text-${randomUUID()}.txt`;
}

function uniqueFileName(file: PasteFile): string {
  const ext = extensionForFile(file);
  const name = path.basename((file.fileName ?? "").trim());
  if (name !== "." && name !== path.sep && name !== "") {
    const base = name.slice(0, name.length - path.extname(name).length);
    if (base !== "") {
      return `${sanitize(base) || "pasted-file"}-${randomUUID()}${ext}`;
    }
  }
  return `pasted-file-${randomUUID()}${ext}`;
}

function extensionForFile(file: PasteFile): string {
  if (file.fileName) {
    return path.extname(file.fileName);
  }
  return extensionForMediaType(file.mediaType);
}

function extensionForMediaType(mediaType: string | undefined): string {
  if (!mediaType) {
    return "";
  }
  const ext = extension(mediaType);
  return ext ? `.${ext}` : "";
}

class ExactStreamReader {
  private readonly iterator: AsyncIterator<unknown>;
  private buffered: Buffer<ArrayBufferLike> = Buffer.alloc(0);

  constructor(readable: AsyncIterable<unknown>) {
    this.iterator = readable[Symbol.asyncIterator]();
  }

  async readBytes(bytes: number): Promise<Uint8Array> {
    assertValidByteCount(bytes, "paste content has invalid byte count");
    const chunks: Array<Buffer<ArrayBufferLike>> = [];
    let remaining = bytes;
    while (remaining > 0) {
      const chunk = await this.take(remaining);
      chunks.push(chunk);
      remaining -= chunk.length;
    }
    return Buffer.concat(chunks, bytes);
  }

  async writeTo(writable: Writable, bytes: number): Promise<void> {
    let remaining = bytes;
    while (remaining > 0) {
      const chunk = await this.take(remaining);
      remaining -= chunk.length;
      await writeChunk(writable, chunk);
    }
  }

  private async take(maxBytes: number): Promise<Buffer<ArrayBufferLike>> {
    if (this.buffered.length > 0) {
      const chunk = this.buffered.subarray(0, maxBytes);
      this.buffered = this.buffered.subarray(chunk.length);
      return chunk;
    }

    while (true) {
      const next = await this.iterator.next();
      if (next.done) {
        throw new InvalidReplyError("paste stream ended before expected byte count");
      }

      const chunk = toBuffer(next.value);
      if (chunk.length === 0) {
        continue;
      }
      if (chunk.length > maxBytes) {
        this.buffered = chunk.subarray(maxBytes);
        return chunk.subarray(0, maxBytes);
      }
      return chunk;
    }
  }
}

function toBuffer(chunk: unknown): Buffer<ArrayBufferLike> {
  if (Buffer.isBuffer(chunk)) {
    return chunk;
  }
  if (chunk instanceof Uint8Array) {
    return Buffer.from(chunk.buffer, chunk.byteOffset, chunk.byteLength);
  }
  if (typeof chunk === "string") {
    return Buffer.from(chunk);
  }
  throw new InvalidReplyError(`paste stream returned unsupported chunk: ${typeof chunk}`);
}

async function writeChunk(writable: Writable, chunk: Buffer<ArrayBufferLike>): Promise<void> {
  if (writable.write(chunk)) {
    return;
  }
  const drained = once(writable, "drain");
  const failed = once(writable, "error").then(([error]) => {
    throw error;
  });
  await Promise.race([drained, failed]);
}

async function closeWritable(writable: Writable): Promise<void> {
  const finished = once(writable, "finish");
  const failed = once(writable, "error").then(([error]) => {
    throw error;
  });
  writable.end();
  await Promise.race([finished, failed]);
}

function assertValidByteCount(bytes: number, message: string): void {
  if (!Number.isSafeInteger(bytes) || bytes < 0) {
    throw new InvalidReplyError(message);
  }
}
