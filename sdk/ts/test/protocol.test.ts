import assert from "node:assert/strict";
import test from "node:test";
import {
  encodeRequest,
  focusRequest,
  inputRequest,
  pasteRequest,
  replyModeOf,
  terminalIdRequest,
} from "../src/protocol.js";

test("encodes request envelopes without reply metadata", () => {
  const request = focusRequest({
    tty: "/dev/ttys001",
    direction: "left",
    ack: true,
  });
  const encoded = encodeRequest(request);
  const decoded = JSON.parse(encoded);

  assert.equal(decoded.version, 1);
  assert.equal(decoded.command, "focus");
  assert.equal(decoded.tty, "/dev/ttys001");
  assert.equal(decoded.direction, "left");
  assert.equal(decoded.ack, true);
  assert.equal(decoded.replyMode, undefined);
});

test("reports reply modes", () => {
  assert.equal(replyModeOf(terminalIdRequest()), "frame");
  assert.equal(replyModeOf(focusRequest({ direction: "left" })), "none");
  assert.equal(replyModeOf(focusRequest({ direction: "left", ack: true })), "frame");
  assert.equal(replyModeOf(inputRequest({ text: "echo hi" })), "none");
  assert.equal(replyModeOf(inputRequest({ text: "echo hi", ack: true })), "frame");
  assert.equal(replyModeOf(pasteRequest()), "stream");
});

test("encodes input requests with optional booleans omitted unless true", () => {
  assert.deepEqual(
    inputRequest({
      tty: "/dev/ttys001",
      focused: false,
      text: "echo hi",
      submit: false,
      ack: false,
    }),
    {
      version: 1,
      command: "input",
      tty: "/dev/ttys001",
      text: "echo hi",
    },
  );

  assert.deepEqual(
    inputRequest({
      tty: "/dev/ttys001",
      focused: true,
      text: "echo hi",
      submit: true,
      ack: true,
    }),
    {
      version: 1,
      command: "input",
      tty: "/dev/ttys001",
      focused: true,
      text: "echo hi",
      submit: true,
      ack: true,
    },
  );
});
