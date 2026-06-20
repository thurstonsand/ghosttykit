import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { fileNotification, pasteEditorText, runGtyPaste } from "./gty.js";
import { loadSettings } from "./settings.js";

export default function piPaste(pi: ExtensionAPI): void {
  const settings = loadSettings();

  async function paste(ctx: ExtensionContext): Promise<void> {
    try {
      const result = await runGtyPaste(
        async (command, args) => {
          const execResult = await pi.exec(command, args, { timeout: 120_000 });
          return {
            stdout: execResult.stdout,
            stderr: execResult.stderr,
            code: execResult.code,
          };
        },
        settings.gtyBin,
        settings.outputDir,
      );

      ctx.ui.pasteToEditor(pasteEditorText(result));
      const notification = fileNotification(result);
      if (notification) {
        ctx.ui.notify(notification, "info");
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
