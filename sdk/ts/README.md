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
const reply = await gty.doctor();

console.log(reply.healthy);
```

By default, the client connects to `GTY_SOCK` when set, otherwise the standard local daemon socket. Pass `socketPath` to target another daemon or bridge socket:

```ts
const gty = client({ socketPath: "/path/to/ghosttykit.sock" });
```

## Commands

```ts
await gty.doctor();
await gty.terminalId({ focused: true });
await gty.tabTerminalCount({ focused: true });
await gty.keyTableActivate({ table: "nvim", focused: true, ack: true });
await gty.keyTableDeactivate({ focused: true, ack: true });
await gty.focus({ direction: "left", focused: true, ack: true });
await gty.split({
  direction: "right",
  cwd: process.cwd(),
  focus: "new",
  ack: true,
});
await gty.resize({ direction: "right", amount: { pixels: 40 }, ack: true });
await gty.zoom({ ack: true });
await gty.clearCache({ ack: true });
await gty.bridgeCreate({ focused: true });
await gty.bridgeLease(token);
```

Paste returns the daemon's streamed paste body. Consumers decide whether to insert text, write files, or perform another action:

```ts
const paste = await gty.paste();

try {
  if (paste.header.kind === "text") {
    // Read exactly paste.header.bytes from paste.body.
  } else {
    // Read each file payload from paste.body in paste.header.files order.
  }
} finally {
  paste.close();
}
```

For lower-level integrations, request builders are exported:

```ts
import { client, focusRequest } from "@thurstonsand/ghosttykit";

await client().call(focusRequest({ direction: "left", ack: true }));
```

## Errors

Failed daemon replies throw typed errors based on the protocol code:

```ts
import { PasteEmptyError } from "@thurstonsand/ghosttykit";

try {
  await client().paste();
} catch (error) {
  if (error instanceof PasteEmptyError) {
    // Clipboard has no supported paste content.
  }
}
```

Transport and client-shape failures throw non-protocol errors such as `TransportError`, `InvalidReplyModeError`, and `InvalidReplyError`.

## Development

From this repository:

```sh
cd sdk/ts
npm install
npm run check
```
