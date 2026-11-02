import { type ProtocolCode, protocolCodes } from "./codes.js";

export const protocolVersion = 1;

export type ReplyMode = "frame" | "none" | "stream" | "hold";

const replyModes = new WeakMap<RequestEnvelope, ReplyMode>();

export interface RequestEnvelope {
  version: typeof protocolVersion;
  command: string;
}

export interface FrameReply {
  version: number;
  code: ProtocolCode | string;
  value?: string;
  error?: string;
}

export interface DoctorReply extends FrameReply {
  healthy: boolean;
  checks?: DoctorCheck[];
}

export interface DoctorCheck {
  name: string;
  status: string;
  message?: string;
}

export interface BridgeCreateReply extends FrameReply {
  socketPath?: string;
  leaseToken?: string;
}

export type Direction = "left" | "down" | "up" | "right";
export type FocusTarget = "new" | "original";

export type ResizeAmount = { pixels: number } | { percent: number };

/**
 * Names the terminal a terminal-scoped request acts on. `tty` is an explicit target; `callerTty`
 * is the terminal the client detected for itself. The main daemon prefers `tty` and rejects a
 * request with neither. A bridge acts only on the terminal that created it: it rejects `tty` and
 * ignores `callerTty`, which names a terminal on the remote host.
 */
export interface TerminalTargetOptions {
  tty?: string;
  callerTty?: string;
}

export interface TerminalIdOptions extends TerminalTargetOptions {
  refresh?: boolean;
}

export interface AckOptions extends TerminalTargetOptions {
  ack?: boolean;
}

export interface KeyTableActivateOptions extends AckOptions {
  table: string;
}

export interface DirectionOptions extends AckOptions {
  direction: Direction;
}

export interface SplitOptions extends DirectionOptions {
  cwd?: string;
  commandText?: string;
  focus?: FocusTarget;
}

export interface InputOptions extends AckOptions {
  text: string;
  submit?: boolean;
}

export interface ResizeOptions extends DirectionOptions {
  amount: ResizeAmount;
}

export interface BridgeLeaseOptions {
  token: string;
}

export interface Request extends RequestEnvelope {
  [key: string]: unknown;
}

export interface PasteFrameFile {
  fileName?: string;
  mediaType?: string;
  bytes: number;
  source?: string;
}

export interface PasteStreamFrameHeader extends FrameReply {
  kind?: "text" | "files";
  files?: PasteFrameFile[];
  bytes?: number;
}

export type PasteStreamHeader =
  | (PasteStreamFrameHeader & { kind: "text"; bytes: number })
  | (PasteStreamFrameHeader & {
      kind: "files";
      files: PasteFrameFile[];
      bytes: number;
    });

export function replyModeOf(request: RequestEnvelope): ReplyMode {
  return replyModes.get(request) ?? "frame";
}

export function encodeRequest(request: RequestEnvelope): string {
  return `${JSON.stringify(request)}\n`;
}

export function doctorRequest(): Request {
  return envelope("doctor");
}

export function terminalIdRequest(options: TerminalIdOptions): Request {
  return compact({
    ...envelope("terminal-id"),
    tty: options.tty,
    callerTty: options.callerTty,
    refresh: optionalTrue(options.refresh),
  });
}

export function tabTerminalCountRequest(options: TerminalTargetOptions): Request {
  return compact({
    ...envelope("tab-terminal-count"),
    tty: options.tty,
    callerTty: options.callerTty,
  });
}

export interface ClearCacheOptions extends TerminalTargetOptions {
  all?: boolean;
  ack?: boolean;
}

export function clearCacheRequest(options: ClearCacheOptions = {}): Request {
  return withReplyMode(
    compact({
      ...envelope("clear-cache"),
      tty: options.tty,
      callerTty: options.callerTty,
      all: optionalTrue(options.all),
      ack: optionalTrue(options.ack),
    }),
    ackReplyMode(options.ack),
  );
}

export function keyTableActivateRequest(options: KeyTableActivateOptions): Request {
  return withReplyMode(
    compact({
      ...envelope("key-table-activate"),
      tty: options.tty,
      callerTty: options.callerTty,
      table: options.table,
      ack: optionalTrue(options.ack),
    }),
    ackReplyMode(options.ack),
  );
}

export function keyTableDeactivateRequest(options: AckOptions): Request {
  return withReplyMode(
    compact({
      ...envelope("key-table-deactivate"),
      tty: options.tty,
      callerTty: options.callerTty,
      ack: optionalTrue(options.ack),
    }),
    ackReplyMode(options.ack),
  );
}

export function focusRequest(options: DirectionOptions): Request {
  return withReplyMode(
    compact({
      ...envelope("focus"),
      tty: options.tty,
      callerTty: options.callerTty,
      direction: options.direction,
      ack: optionalTrue(options.ack),
    }),
    ackReplyMode(options.ack),
  );
}

export function splitRequest(options: SplitOptions): Request {
  return withReplyMode(
    compact({
      ...envelope("split"),
      tty: options.tty,
      callerTty: options.callerTty,
      direction: options.direction,
      cwd: options.cwd,
      commandText: options.commandText,
      focus: options.focus,
      ack: optionalTrue(options.ack),
    }),
    ackReplyMode(options.ack),
  );
}

export function inputRequest(options: InputOptions): Request {
  return withReplyMode(
    compact({
      ...envelope("input"),
      tty: options.tty,
      callerTty: options.callerTty,
      text: options.text,
      submit: optionalTrue(options.submit),
      ack: optionalTrue(options.ack),
    }),
    ackReplyMode(options.ack),
  );
}

export function resizeRequest(options: ResizeOptions): Request {
  return withReplyMode(
    compact({
      ...envelope("resize"),
      tty: options.tty,
      callerTty: options.callerTty,
      direction: options.direction,
      amount: options.amount,
      ack: optionalTrue(options.ack),
    }),
    ackReplyMode(options.ack),
  );
}

export function zoomRequest(options: AckOptions): Request {
  return withReplyMode(
    compact({
      ...envelope("zoom"),
      tty: options.tty,
      callerTty: options.callerTty,
      ack: optionalTrue(options.ack),
    }),
    ackReplyMode(options.ack),
  );
}

export function pasteRequest(): Request {
  return withReplyMode(envelope("paste"), "stream");
}

export function bridgeCreateRequest(options: TerminalTargetOptions): Request {
  return compact({
    ...envelope("bridge-create"),
    tty: options.tty,
    callerTty: options.callerTty,
  });
}

export function bridgeLeaseRequest(token: string): Request {
  return withReplyMode(
    {
      ...envelope("bridge-lease"),
      token,
    },
    "hold",
  );
}

export type { ProtocolCode };
export { protocolCodes };

function envelope(command: string): Request {
  return { version: protocolVersion, command };
}

function ackReplyMode(ack: boolean | undefined): ReplyMode {
  return ack ? "frame" : "none";
}

function optionalTrue(value: boolean | undefined): true | undefined {
  return value ? true : undefined;
}

function compact<T extends Record<string, unknown>>(value: T): T {
  for (const key of Object.keys(value)) {
    if (value[key] === undefined) {
      delete value[key];
    }
  }
  return value;
}

function withReplyMode<T extends RequestEnvelope>(request: T, mode: ReplyMode): T {
  replyModes.set(request, mode);
  return request;
}
