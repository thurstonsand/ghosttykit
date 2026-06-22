import net from "node:net";
import os from "node:os";
import path from "node:path";
import { TransportError } from "./errors.js";

export function defaultSocketPath(): string {
  return path.join(os.homedir(), ".local/run/ghosttykit/ghosttykitd.sock");
}

export function socketPath(options: { socketPath?: string } = {}): string {
  return options.socketPath || process.env.GTY_SOCK || defaultSocketPath();
}

export function dial(socketPathValue: string): Promise<net.Socket> {
  if (!socketPathValue.trim()) {
    return Promise.reject(new TransportError("socket path is empty"));
  }

  return new Promise((resolve, reject) => {
    const socket = net.createConnection({ path: socketPathValue });
    let settled = false;

    function settle<T>(handler: (value: T) => void, value: T): void {
      if (settled) {
        return;
      }
      settled = true;
      socket.off("connect", onConnect);
      socket.off("error", onError);
      handler(value);
    }

    function onConnect(): void {
      settle(resolve, socket);
    }

    function onError(error: Error): void {
      settle(
        reject,
        new TransportError(`connect ${socketPathValue}: ${error.message}`, {
          cause: error,
        }),
      );
    }

    socket.once("connect", onConnect);
    socket.once("error", onError);
  });
}
