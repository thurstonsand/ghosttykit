import { execFileSync } from "node:child_process";

let derivedTTY: string | undefined;

/**
 * Normalizes an explicit tty value, or derives the caller's: GTY_TTY first, then the process's
 * own controlling terminal. The daemon requires a tty on every terminal-targeted request.
 */
export function resolveTTY(value?: string): string {
  if (value) {
    return normalizeTTY(value);
  }
  const env = process.env.GTY_TTY;
  if (env) {
    return normalizeTTY(env);
  }
  derivedTTY ??= currentTTY();
  return derivedTTY;
}

function normalizeTTY(value: string): string {
  return value.startsWith("/dev/") ? value : `/dev/${value}`;
}

function currentTTY(): string {
  for (const fd of [0, 1, 2]) {
    try {
      const output = execFileSync("tty", { stdio: [fd, "pipe", "ignore"] })
        .toString()
        .trim();
      if (output && output !== "not a tty") {
        return normalizeTTY(output);
      }
    } catch {
      // try the next descriptor
    }
  }
  throw new Error("no tty: pass tty explicitly or set GTY_TTY");
}
