import type net from "node:net";
import { PassThrough, type Readable } from "node:stream";
import {
  InvalidReplyError,
  InvalidReplyModeError,
  TransportError,
  throwIfReplyError,
} from "./errors.js";
import {
  type AckOptions,
  type BridgeCreateReply,
  bridgeCreateRequest,
  bridgeLeaseRequest,
  clearCacheRequest,
  type DirectionOptions,
  type DoctorReply,
  doctorRequest,
  encodeRequest,
  type FrameReply,
  focusRequest,
  type KeyTableActivateOptions,
  keyTableActivateRequest,
  keyTableDeactivateRequest,
  type PasteOptions,
  type PasteStreamFrameHeader,
  type PasteStreamHeader,
  pasteRequest,
  type Request,
  type ResizeOptions,
  replyModeOf,
  resizeRequest,
  type SplitOptions,
  splitRequest,
  type TerminalIdOptions,
  type TerminalTargetOptions,
  tabTerminalCountRequest,
  terminalIdRequest,
  zoomRequest,
} from "./protocol.js";
import { dial, socketPath as resolveSocketPath } from "./socket.js";

export interface ClientOptions {
  socketPath?: string;
}

export interface PasteStream {
  header: PasteStreamHeader;
  body: Readable;
  close(): void;
}

export interface HoldResult<T extends FrameReply = FrameReply> {
  reply: T;
  close(): void;
}

export class GhosttyKitClient {
  readonly socketPath: string;

  constructor(options: ClientOptions = {}) {
    this.socketPath = resolveSocketPath(options);
  }

  async call<T extends FrameReply = FrameReply>(request: Request): Promise<T> {
    requireReplyMode(request, "frame");
    validateRequest(request);
    const socket = await dial(this.socketPath);
    try {
      await writeRequest(socket, request);
      const reply = await readJsonLine<T>(socket);
      throwIfReplyError(reply);
      return reply;
    } finally {
      socket.destroy();
    }
  }

  async notify(request: Request): Promise<void> {
    requireReplyMode(request, "none");
    validateRequest(request);
    const socket = await dial(this.socketPath);
    try {
      await writeRequest(socket, request);
      await waitForEOF(socket);
    } finally {
      socket.destroy();
    }
  }

  async stream<T extends FrameReply = FrameReply>(
    request: Request,
  ): Promise<{ header: T; body: Readable; close(): void }> {
    requireReplyMode(request, "stream");
    validateRequest(request);
    const socket = await dial(this.socketPath);
    try {
      await writeRequest(socket, request);
      const { value: header, rest } = await readJsonLineWithRest<T>(socket);
      throwIfReplyError(header);
      const body = new PassThrough();
      if (rest.length > 0) {
        body.write(rest);
      }
      socket.pipe(body);
      return { header, body, close: () => socket.destroy() };
    } catch (error) {
      socket.destroy();
      throw error;
    }
  }

  async hold<T extends FrameReply = FrameReply>(request: Request): Promise<HoldResult<T>> {
    requireReplyMode(request, "hold");
    validateRequest(request);
    const socket = await dial(this.socketPath);
    try {
      await writeRequest(socket, request);
      const reply = await readJsonLine<T>(socket);
      throwIfReplyError(reply);
      return { reply, close: () => socket.destroy() };
    } catch (error) {
      socket.destroy();
      throw error;
    }
  }

  async notifyAck(request: Request, ack?: boolean): Promise<FrameReply | undefined> {
    if (ack) {
      return this.call(request);
    }
    await this.notify(request);
    return undefined;
  }

  doctor(): Promise<DoctorReply> {
    return this.call<DoctorReply>(doctorRequest());
  }

  terminalId(options: TerminalIdOptions = {}): Promise<FrameReply> {
    return this.call(terminalIdRequest(options));
  }

  tabTerminalCount(options: TerminalTargetOptions = {}): Promise<FrameReply> {
    return this.call(tabTerminalCountRequest(options));
  }

  clearCache(options: { tty?: string; ack?: boolean } = {}): Promise<FrameReply | undefined> {
    return this.notifyAck(clearCacheRequest(options), options.ack);
  }

  keyTableActivate(options: KeyTableActivateOptions): Promise<FrameReply | undefined> {
    return this.notifyAck(keyTableActivateRequest(options), options.ack);
  }

  keyTableDeactivate(options: AckOptions = {}): Promise<FrameReply | undefined> {
    return this.notifyAck(keyTableDeactivateRequest(options), options.ack);
  }

  focus(options: DirectionOptions): Promise<FrameReply | undefined> {
    return this.notifyAck(focusRequest(options), options.ack);
  }

  split(options: SplitOptions): Promise<FrameReply | undefined> {
    return this.notifyAck(splitRequest(options), options.ack);
  }

  resize(options: ResizeOptions): Promise<FrameReply | undefined> {
    return this.notifyAck(resizeRequest(options), options.ack);
  }

  zoom(options: AckOptions = {}): Promise<FrameReply | undefined> {
    return this.notifyAck(zoomRequest(options), options.ack);
  }

  async paste(options: PasteOptions = {}): Promise<PasteStream> {
    const result = await this.stream<PasteStreamFrameHeader>(pasteRequest(options));
    return {
      header: normalizePasteHeader(result.header),
      body: result.body,
      close: result.close,
    };
  }

  bridgeCreate(options: TerminalTargetOptions = {}): Promise<BridgeCreateReply> {
    return this.call<BridgeCreateReply>(bridgeCreateRequest(options));
  }

  bridgeLease(token: string): Promise<HoldResult> {
    return this.hold(bridgeLeaseRequest(token));
  }
}

export function client(options: ClientOptions = {}): GhosttyKitClient {
  return new GhosttyKitClient(options);
}

function requireReplyMode(request: Request, want: string): void {
  const got = replyModeOf(request);
  if (got !== want) {
    throw new InvalidReplyModeError(`request reply mode is ${got}, not ${want}`);
  }
}

function validateRequest(request: Request): void {
  if (
    request.command === "terminal-id" &&
    request.refresh === true &&
    request.tty &&
    request.focused !== true
  ) {
    throw new InvalidReplyError("cannot refresh terminal-id if it is not the focused window");
  }
  if (request.command === "resize") {
    validateResizeAmount(request.amount);
  }
}

function validateResizeAmount(amount: unknown): void {
  if (!amount || typeof amount !== "object") {
    throw new InvalidReplyError("resize amount is required");
  }
  const value = amount as { pixels?: unknown; percent?: unknown };
  const hasPixels = value.pixels !== undefined;
  const hasPercent = value.percent !== undefined;
  if (hasPixels === hasPercent) {
    throw new InvalidReplyError("resize amount must specify exactly one of pixels or percent");
  }
}

function normalizePasteHeader(header: PasteStreamFrameHeader): PasteStreamHeader {
  if (header.kind === "text" && typeof header.bytes === "number") {
    return header as PasteStreamHeader;
  }
  if (header.kind === "files" && Array.isArray(header.files) && typeof header.bytes === "number") {
    return header as PasteStreamHeader;
  }
  throw new InvalidReplyError("invalid paste stream header");
}

function writeRequest(socket: net.Socket, request: Request): Promise<void> {
  return new Promise((resolve, reject) => {
    socket.write(encodeRequest(request), (error) => {
      if (error) {
        reject(
          new TransportError(`send request: ${error.message}`, {
            cause: error,
          }),
        );
        return;
      }
      resolve();
    });
  });
}

async function readJsonLine<T>(socket: net.Socket): Promise<T> {
  const { value, rest } = await readJsonLineWithRest<T>(socket);
  if (rest.length > 0) {
    socket.unshift(rest);
  }
  return value;
}

async function readJsonLineWithRest<T>(socket: net.Socket): Promise<{ value: T; rest: Buffer }> {
  const { line, rest } = await readLine(socket);
  try {
    return { value: JSON.parse(line) as T, rest };
  } catch (error) {
    throw new InvalidReplyError("decode reply", { cause: error });
  }
}

function readLine(socket: net.Socket): Promise<{ line: string; rest: Buffer }> {
  return new Promise((resolve, reject) => {
    const chunks: Buffer[] = [];
    let totalBytes = 0;

    function cleanup(): void {
      socket.off("data", onData);
      socket.off("error", onError);
      socket.off("end", onEnd);
    }

    function onData(chunk: Buffer): void {
      const newlineIndex = chunk.indexOf(0x0a);
      if (newlineIndex === -1) {
        chunks.push(chunk);
        totalBytes += chunk.length;
        return;
      }

      const lineChunk = chunk.subarray(0, newlineIndex);
      const rest = chunk.subarray(newlineIndex + 1);
      chunks.push(lineChunk);
      totalBytes += lineChunk.length;
      cleanup();
      resolve({
        line: Buffer.concat(chunks, totalBytes).toString("utf8"),
        rest,
      });
    }

    function onError(error: Error): void {
      cleanup();
      reject(new TransportError(`read reply: ${error.message}`, { cause: error }));
    }

    function onEnd(): void {
      cleanup();
      reject(new TransportError("read reply: unexpected EOF"));
    }

    socket.on("data", onData);
    socket.once("error", onError);
    socket.once("end", onEnd);
  });
}

function waitForEOF(socket: net.Socket): Promise<void> {
  return new Promise((resolve, reject) => {
    function cleanup(): void {
      socket.off("data", onData);
      socket.off("error", onError);
      socket.off("end", onEnd);
    }

    function onData(): void {
      cleanup();
      reject(new InvalidReplyError("daemon sent unexpected data for no-reply request"));
    }

    function onError(error: Error): void {
      cleanup();
      reject(
        new TransportError(`wait for daemon completion: ${error.message}`, {
          cause: error,
        }),
      );
    }

    function onEnd(): void {
      cleanup();
      resolve();
    }

    socket.once("data", onData);
    socket.once("error", onError);
    socket.once("end", onEnd);
  });
}
