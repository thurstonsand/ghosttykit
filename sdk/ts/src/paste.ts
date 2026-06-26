export type Paste = TextPaste | FilesPaste;
export type PasteState = "pending" | "consuming" | "consumed";

export interface TextPaste {
  readonly kind: "text";
  readonly byteLength: number;
  readonly state: PasteState;
  readonly consumed: boolean;

  text(): Promise<string>;
  raw(): Promise<Uint8Array>;
  save(outputDir: string): Promise<readonly SavedPasteFile[]>;
}

export interface FilesPaste {
  readonly kind: "files";
  readonly byteLength: number;
  readonly files: readonly PasteFile[];
  readonly state: PasteState;
  readonly consumed: boolean;

  contents(): Promise<readonly PasteFileContent[]>;
  save(outputDir: string): Promise<readonly SavedPasteFile[]>;
}

export interface PasteFile {
  readonly fileName?: string;
  readonly mediaType?: string;
  readonly byteLength: number;
  readonly source?: string;
}

export interface PasteFileContent extends PasteFile {
  readonly data: Uint8Array;
}

export interface SavedPasteFile extends PasteFile {
  readonly path: string;
}

export interface PasteMatcher<T> {
  text: (paste: TextPaste) => T | Promise<T>;
  files: (paste: FilesPaste) => T | Promise<T>;
}

export const Paste = {
  match<T>(paste: Paste, matcher: PasteMatcher<T>): T | Promise<T> {
    switch (paste.kind) {
      case "text":
        return matcher.text(paste);
      case "files":
        return matcher.files(paste);
    }
  },

  isText(paste: Paste): paste is TextPaste {
    return paste.kind === "text";
  },

  isFiles(paste: Paste): paste is FilesPaste {
    return paste.kind === "files";
  },
};
