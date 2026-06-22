import assert from "node:assert/strict";
import { mkdtemp, rm } from "node:fs/promises";
import net from "node:net";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { GhosttyKitClient } from "../src/client.js";
import { InvalidReplyModeError, PasteEmptyError } from "../src/errors.js";
import { doctorRequest, focusRequest, pasteRequest } from "../src/protocol.js";
import { socketPath } from "../src/socket.js";

test("call rejects stream requests", async () => {
  const client = new GhosttyKitClient({ socketPath: "unused.sock" });
  await assert.rejects(client.call(pasteRequest()), InvalidReplyModeError);
});

test("stream rejects frame requests", async () => {
  const client = new GhosttyKitClient({ socketPath: "unused.sock" });
  await assert.rejects(client.stream(doctorRequest()), InvalidReplyModeError);
});

test("call maps protocol errors", async () => {
  await withServer(
    async (socket) => {
      await readRequest(socket);
      socket.end('{"version":1,"code":"paste_empty","error":"clipboard empty"}\n');
    },
    async (socketPathValue) => {
      const client = new GhosttyKitClient({ socketPath: socketPathValue });
      await assert.rejects(client.call(doctorRequest()), PasteEmptyError);
    },
  );
});

test("stream preserves body bytes buffered with header", async () => {
  await withServer(
    async (socket) => {
      await readRequest(socket);
      socket.end('{"version":1,"code":"ok","kind":"text","bytes":11}\nhello world');
    },
    async (socketPathValue) => {
      const client = new GhosttyKitClient({ socketPath: socketPathValue });
      const paste = await client.paste();
      const chunks: Buffer[] = [];
      for await (const chunk of paste.body) {
        chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
      }

      assert.equal(paste.header.kind, "text");
      assert.equal(paste.header.bytes, 11);
      assert.equal(Buffer.concat(chunks).toString("utf8"), "hello world");
    },
  );
});

test("notify waits for daemon close without reply bytes", async () => {
  await withServer(
    async (socket) => {
      await readRequest(socket);
      socket.end();
    },
    async (socketPathValue) => {
      const client = new GhosttyKitClient({ socketPath: socketPathValue });
      await client.notify(focusRequest({ direction: "left" }));
    },
  );
});

test("socketPath prefers explicit path, then GTY_SOCK", () => {
  const previous = process.env.GTY_SOCK;
  process.env.GTY_SOCK = "/tmp/gty.sock";
  try {
    assert.equal(socketPath({ socketPath: "/tmp/explicit.sock" }), "/tmp/explicit.sock");
    assert.equal(socketPath(), "/tmp/gty.sock");
  } finally {
    if (previous === undefined) {
      delete process.env.GTY_SOCK;
    } else {
      process.env.GTY_SOCK = previous;
    }
  }
});

async function withServer(
  handle: (socket: net.Socket) => Promise<void>,
  run: (socketPath: string) => Promise<void>,
): Promise<void> {
  const directory = await mkdtemp(path.join(os.tmpdir(), "ghosttykit-ts-"));
  const socketPathValue = path.join(directory, "daemon.sock");
  const server = net.createServer((socket) => {
    void handle(socket).catch((error) => socket.destroy(error));
  });

  try {
    await new Promise<void>((resolve, reject) => {
      server.once("error", reject);
      server.listen(socketPathValue, resolve);
    });
    await run(socketPathValue);
  } finally {
    await new Promise<void>((resolve, reject) => {
      server.close((error) => (error ? reject(error) : resolve()));
    });
    await rm(directory, { recursive: true, force: true });
  }
}

function readRequest(socket: net.Socket): Promise<unknown> {
  return new Promise((resolve, reject) => {
    let data = "";
    socket.on("data", (chunk: Buffer) => {
      data += chunk.toString("utf8");
      if (!data.includes("\n")) {
        return;
      }
      try {
        resolve(JSON.parse(data.split("\n", 1)[0] ?? ""));
      } catch (error) {
        reject(error);
      }
    });
    socket.once("error", reject);
  });
}
