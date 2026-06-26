import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { receivePaste } from "./paste.js";
import { loadSettings } from "./settings.js";

export default function piPaste(pi: ExtensionAPI): void {
  const settings = loadSettings();

  async function paste(ctx: ExtensionContext): Promise<void> {
    try {
      const result = await receivePaste(settings.outputDir);

      ctx.ui.pasteToEditor(result.editorText);
      if (result.notification) {
        ctx.ui.notify(result.notification, "info");
      }
    } catch (error) {
      ctx.ui.notify(`Paste failed: ${errorMessage(error)}`, "error");
    }
  }

  pi.registerShortcut(settings.shortcut, {
    description: "Paste clipboard text or files through GhosttyKit",
    handler: paste,
  });

  pi.registerCommand("paste", {
    description: "Paste clipboard text or files through GhosttyKit",
    handler: async (_args, ctx) => {
      await paste(ctx);
    },
  });
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
