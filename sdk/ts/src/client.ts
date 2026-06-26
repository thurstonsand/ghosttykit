import type net from "node:net";
import { PassThrough, type Readable } from "node:stream";
import {
  InvalidReplyError,
  InvalidReplyModeError,
  TransportError,
  throwIfReplyError,
} from "./errors.js";
import type { Paste } from "./paste.js";
import { pasteFromStream } from "./paste-internal.js";
import {
  type AckOptions,
  type BridgeCreateReply,
  bridgeCreateRequest,
  bridgeLeaseRequest,
  clearCacheRequest,
  type Direction,
  type DoctorCheck,
  type DoctorReply,
  doctorRequest,
  encodeRequest,
  type FocusTarget,
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
  type ResizeAmount,
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

export interface DoctorStatus {
  healthy: boolean;
  checks: readonly DoctorCheck[];
}

export interface RawStream<T extends FrameReply = FrameReply> {
  header: T;
  body: Readable;
  close(): void;
}

export interface HoldResult<T extends FrameReply = FrameReply> {
  reply: T;
  close(): void;
}

export interface Bridge {
  readonly socketPath: string;
  close(): void;
}

export interface CommandOptions extends AckOptions {}

export interface TerminalOptions extends TerminalTargetOptions {
  tty: string;
}

export interface TerminalCommandOptions extends TerminalOptions {
  ack?: boolean;
}

export interface SplitCommandOptions extends TerminalCommandOptions {
  cwd?: string;
  commandText?: string;
  focus?: FocusTarget;
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

  async stream<T extends FrameReply = FrameReply>(request: Request): Promise<RawStream<T>> {
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

  async doctor(): Promise<DoctorStatus> {
    const reply = await this.call<DoctorReply>(doctorRequest());
    return { healthy: reply.healthy, checks: reply.checks ?? [] };
  }

  async terminalId(options: TerminalIdOptions = {}): Promise<string> {
    const reply = await this.call(terminalIdRequest(options));
    return requiredReplyValue(reply, "terminal-id reply missing terminal ID");
  }

  async tabTerminalCount(options: TerminalTargetOptions = {}): Promise<number> {
    const reply = await this.call(tabTerminalCountRequest(options));
    const value = Number.parseInt(
      requiredReplyValue(reply, "tab-terminal-count reply missing count"),
      10,
    );
    if (!Number.isSafeInteger(value)) {
      throw new InvalidReplyError("tab-terminal-count reply has invalid count");
    }
    return value;
  }

  async clearCache(options: CommandOptions = {}): Promise<void> {
    await this.send(clearCacheRequest(options), options.ack);
  }

  async keyTableActivate(table: string, options: TerminalCommandOptions): Promise<void> {
    const requestOptions: KeyTableActivateOptions = { ...options, table };
    await this.send(keyTableActivateRequest(requestOptions), options.ack);
  }

  async keyTableDeactivate(options: TerminalCommandOptions): Promise<void> {
    await this.send(keyTableDeactivateRequest(options), options.ack);
  }

  async focus(direction: Direction, options: TerminalCommandOptions): Promise<void> {
    await this.send(focusRequest({ ...options, direction }), options.ack);
  }

  async split(direction: Direction, options: SplitCommandOptions): Promise<void> {
    const requestOptions: SplitOptions = { ...options, direction };
    await this.send(splitRequest(requestOptions), options.ack);
  }

  async resize(
    direction: Direction,
    amount: ResizeAmount,
    options: TerminalCommandOptions,
  ): Promise<void> {
    await this.send(resizeRequest({ ...options, direction, amount }), options.ack);
  }

  async zoom(options: CommandOptions = {}): Promise<void> {
    await this.send(zoomRequest(options), options.ack);
  }

  async paste(options: PasteOptions = {}): Promise<Paste> {
    const result = await this.stream<PasteStreamFrameHeader>(pasteRequest(options));
    return pasteFromStream(normalizePasteHeader(result.header), result.body, result.close);
  }

  async bridge(options: TerminalOptions): Promise<Bridge> {
    const reply = await this.call<BridgeCreateReply>(bridgeCreateRequest(options));
    if (!reply.socketPath || !reply.leaseToken) {
      throw new InvalidReplyError("bridge-create reply missing socket path or lease token");
    }
    const lease = await new GhosttyKitClient({ socketPath: reply.socketPath }).hold(
      bridgeLeaseRequest(reply.leaseToken),
    );
    return { socketPath: reply.socketPath, close: lease.close };
  }

  private async send(request: Request, ack?: boolean): Promise<void> {
    if (ack) {
      await this.call(request);
      return;
    }
    await this.notify(request);
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

function requiredReplyValue(reply: FrameReply, message: string): string {
  if (typeof reply.value !== "string" || reply.value === "") {
    throw new InvalidReplyError(message);
  }
  return reply.value;
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
