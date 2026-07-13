# @thurstonsand/ghosttykit

TypeScript SDK for GhosttyKit daemon and bridge clients.

Use this package from Node.js tools that need to talk to `ghosttykitd` or a GhosttyKit bridge socket.

## Install

Install GhosttyKit on your Mac. See the root [GhosttyKit README](../../README.md#install) for the full install flow.

```sh
brew install thurstonsand/ghosttykit/ghosttykit
open -a Ghostty
brew services start thurstonsand/ghosttykit/ghosttykit
gty doctor
```

Install the SDK:

```sh
npm install @thurstonsand/ghosttykit
```

Use matching nightlies if you want to track the latest changes:

```sh
brew install thurstonsand/ghosttykit/ghosttykit-nightly
brew services start thurstonsand/ghosttykit/ghosttykit-nightly
npm install @thurstonsand/ghosttykit@nightly
```

## Usage

Create a client and call GhosttyKit commands:

```ts
import { client } from "@thurstonsand/ghosttykit";

const gty = client();
const status = await gty.doctor();

console.log(status.healthy);
```

By default, the client connects to `GTY_SOCK` when set, otherwise the standard local daemon socket. Pass `socketPath` to target another daemon or bridge socket:

```ts
const gty = client({ socketPath: "/path/to/ghosttykit.sock" });
```

## Commands

Terminal-scoped methods derive `tty` from `GTY_TTY`, then the process's controlling terminal, when it is omitted. Pass `tty` explicitly to override it. Raw protocol request builders require a resolved `tty`.

```ts
await gty.doctor(); // DoctorStatus
await gty.terminalId(); // string
await gty.tabTerminalCount(); // number

await gty.keyTableActivate("nvim", { ack: true });
await gty.keyTableDeactivate({ ack: true });
await gty.focus("left", { ack: true });
await gty.split("right", {
  cwd: process.cwd(),
  focus: "new",
  ack: true,
});
await gty.resize("right", { pixels: 40 }, { ack: true });
await gty.zoom({ ack: true });
await gty.clearCache({ ack: true });
```

Create a bridge lease:

```ts
const bridge = await gty.bridge();
try {
  console.log(bridge.socketPath);
} finally {
  bridge.close();
}
```

## Paste

`paste()` returns a consumable discriminated union. Use `Paste.match` for exhaustive handling, or switch on `paste.kind` directly.

```ts
import { Paste, client } from "@thurstonsand/ghosttykit";

const paste = await client().paste();

const editorText = await Paste.match(paste, {
  text: (paste) => paste.text(),
  files: async (paste) => {
    const files = await paste.save("/tmp/pi-paste-file");
    return files.map((file) => `@${file.path}`).join(" ");
  },
});
```

Paste payloads are streams. Calling `text()`, `raw()`, `contents()`, or `save()` consumes the paste. `paste.state` reports `"pending"`, `"consuming"`, or `"consumed"`; a second consume attempt throws `PasteConsumedError`.

Text paste methods:

```ts
if (paste.kind === "text") {
  await paste.text(); // string
  await paste.raw(); // Uint8Array
  await paste.save("/tmp/paste-output"); // pasted-text-<uuid>.txt
}
```

File paste methods:

```ts
if (paste.kind === "files") {
  paste.files; // metadata
  await paste.contents(); // metadata plus actual files as Uint8Array
  await paste.save("/tmp/paste-output"); // metadata plus saved path
}
```

## Protocol escape hatch

Low-level protocol requests are available through the `protocol` namespace when you need direct control:

```ts
import { client, protocol } from "@thurstonsand/ghosttykit";

const gty = client();
const stream = await gty.stream<protocol.PasteStreamFrameHeader>(
  protocol.pasteRequest(),
);
try {
  if (stream.header.kind === "files") {
    for (const file of stream.header.files ?? []) {
      // Read exactly file.bytes from stream.body.
    }
  }
} finally {
  stream.close();
}
```

Raw methods are `call`, `notify`, `stream`, and `hold`. They work with request builders from `protocol` and return protocol frames.

## Errors

Failed daemon replies throw typed errors based on the protocol code:

```ts
import { PasteEmptyError, client } from "@thurstonsand/ghosttykit";

try {
  await client().paste();
} catch (error) {
  if (error instanceof PasteEmptyError) {
    // Clipboard has no supported content.
  }
}
```

Transport and client-shape failures throw non-protocol errors such as `TransportError`, `InvalidReplyModeError`, `InvalidReplyError`, and `PasteConsumedError`.

## Development

From this repository:

```sh
cd sdk/ts
npm install
npm run check
```
