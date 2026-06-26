import assert from "node:assert/strict";
import { mkdtemp, readdir, readFile, rm } from "node:fs/promises";
import net from "node:net";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { GhosttyKitClient } from "../src/client.js";
import { InvalidReplyModeError, PasteEmptyError } from "../src/errors.js";
import { Paste } from "../src/paste.js";
import {
  doctorRequest,
  focusRequest,
  type PasteStreamFrameHeader,
  pasteRequest,
} from "../src/protocol.js";
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
      const stream = await client.stream<PasteStreamFrameHeader>(pasteRequest());
      const chunks: Buffer[] = [];
      for await (const chunk of stream.body) {
        chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
      }

      assert.equal(stream.header.kind, "text");
      assert.equal(stream.header.bytes, 11);
      assert.equal(Buffer.concat(chunks).toString("utf8"), "hello world");
    },
  );
});

test("paste returns consumable text paste", async () => {
  await withServer(
    async (socket) => {
      await readRequest(socket);
      socket.end('{"version":1,"code":"ok","kind":"text","bytes":11}\nhello world');
    },
    async (socketPathValue) => {
      const client = new GhosttyKitClient({ socketPath: socketPathValue });
      const paste = await client.paste();

      assert.equal(paste.kind, "text");
      assert.equal(paste.byteLength, 11);
      assert.equal(paste.state, "pending");
      assert.equal(await paste.text(), "hello world");
      assert.equal(paste.state, "consumed");
      await assert.rejects(paste.raw(), /already been consumed/);
    },
  );
});

test("paste saves streamed files and exposes metadata", async () => {
  await withServer(
    async (socket) => {
      await readRequest(socket);
      socket.end(
        '{"version":1,"code":"ok","kind":"files","bytes":11,"files":[{"fileName":"../hello world.txt","mediaType":"text/plain","bytes":5,"source":"one"},{"mediaType":"image/png","bytes":6,"source":"two"}]}\nhelloworld!',
      );
    },
    async (socketPathValue) => {
      const outputDir = await mkdtemp(path.join(os.tmpdir(), "ghosttykit-paste-save-"));
      try {
        const client = new GhosttyKitClient({ socketPath: socketPathValue });
        const paste = await client.paste();
        const files = await Paste.match(paste, {
          text: () => assert.fail("expected files paste"),
          files: (paste) => paste.save(outputDir),
        });

        assert.equal(files.length, 2);
        assert.equal(files[0]?.byteLength, 5);
        assert.equal(files[0]?.mediaType, "text/plain");
        assert.match(path.basename(files[0]?.path ?? ""), /^hello world-[0-9a-f-]+\.txt$/);
        assert.match(path.basename(files[1]?.path ?? ""), /^pasted-file-[0-9a-f-]+\.png$/);
        assert.equal(await readFile(files[0]?.path ?? "", "utf8"), "hello");
        assert.equal(await readFile(files[1]?.path ?? "", "utf8"), "world!");
        assert.equal((await readdir(outputDir)).length, 2);
      } finally {
        await rm(outputDir, { recursive: true, force: true });
      }
    },
  );
});

test("text paste can save to a generated text file", async () => {
  await withServer(
    async (socket) => {
      await readRequest(socket);
      socket.end('{"version":1,"code":"ok","kind":"text","bytes":11}\nhello world');
    },
    async (socketPathValue) => {
      const outputDir = await mkdtemp(path.join(os.tmpdir(), "ghosttykit-text-save-"));
      try {
        const client = new GhosttyKitClient({ socketPath: socketPathValue });
        const paste = await client.paste();
        const files = await Paste.match(paste, {
          text: (paste) => paste.save(outputDir),
          files: () => assert.fail("expected text paste"),
        });

        assert.equal(files.length, 1);
        assert.equal(files[0]?.byteLength, 11);
        assert.equal(files[0]?.mediaType, "text/plain");
        assert.match(path.basename(files[0]?.path ?? ""), /^pasted-text-[0-9a-f-]+\.txt$/);
        assert.equal(await readFile(files[0]?.path ?? "", "utf8"), "hello world");
      } finally {
        await rm(outputDir, { recursive: true, force: true });
      }
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
