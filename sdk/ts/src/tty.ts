import { execFileSync } from "node:child_process";
import type { TerminalTargetOptions } from "./protocol.js";

let derivedTTY: string | null | undefined;

/**
 * Makes `value`, or else GTY_TTY, an explicit target. Without either it names the process's own
 * controlling terminal as the caller's, and a process with no terminal names none: whether its
 * endpoint needs one is the daemon's decision.
 */
export function resolveTarget(value?: string): TerminalTargetOptions {
  const explicit = value || process.env.GTY_TTY;
  if (explicit) {
    return { tty: normalizeTTY(explicit) };
  }
  derivedTTY ??= currentTTY();
  return derivedTTY ? { callerTty: derivedTTY } : {};
}

function normalizeTTY(value: string): string {
  return value.startsWith("/dev/") ? value : `/dev/${value}`;
}

function currentTTY(): string | null {
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
  return null;
}
