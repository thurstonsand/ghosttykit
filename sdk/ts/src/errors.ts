import { type ProtocolCode, protocolCodes } from "./codes.js";
import type { FrameReply } from "./protocol.js";

export class GhosttyKitError extends Error {
  readonly code: ProtocolCode | string;

  constructor(code: ProtocolCode | string, message?: string) {
    super(message ? `${code}: ${message}` : code);
    this.name = new.target.name;
    this.code = code;
  }
}

export class ReplyError extends GhosttyKitError {}
export class ProtocolVersionMismatchError extends GhosttyKitError {}
export class UnknownCommandError extends GhosttyKitError {}
export class InvalidRequestError extends GhosttyKitError {}
export class TerminalNotFoundError extends GhosttyKitError {}
export class GhosttyUnavailableError extends GhosttyKitError {}
export class PasteEmptyError extends GhosttyKitError {}
export class PasteUnsupportedError extends GhosttyKitError {}
export class StreamFailedError extends GhosttyKitError {}
export class InternalError extends GhosttyKitError {}

export class TransportError extends Error {
  constructor(message: string, options?: ErrorOptions) {
    super(message, options);
    this.name = "TransportError";
  }
}

export class InvalidReplyModeError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "InvalidReplyModeError";
  }
}

export class InvalidReplyError extends Error {
  constructor(message: string, options?: ErrorOptions) {
    super(message, options);
    this.name = "InvalidReplyError";
  }
}

export class PasteConsumedError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "PasteConsumedError";
  }
}

export function errorFromReply(reply: FrameReply): GhosttyKitError | undefined {
  if (reply.code === protocolCodes.ok) {
    return undefined;
  }

  const code = reply.code;
  const message = reply.error;
  switch (code) {
    case protocolCodes.protocolVersionMismatch:
      return new ProtocolVersionMismatchError(code, message);
    case protocolCodes.unknownCommand:
      return new UnknownCommandError(code, message);
    case protocolCodes.invalidRequest:
      return new InvalidRequestError(code, message);
    case protocolCodes.terminalNotFound:
      return new TerminalNotFoundError(code, message);
    case protocolCodes.ghosttyUnavailable:
      return new GhosttyUnavailableError(code, message);
    case protocolCodes.pasteEmpty:
      return new PasteEmptyError(code, message);
    case protocolCodes.pasteUnsupported:
      return new PasteUnsupportedError(code, message);
    case protocolCodes.streamFailed:
      return new StreamFailedError(code, message);
    case protocolCodes.internalError:
      return new InternalError(code, message);
    default:
      return new ReplyError(code, message);
  }
}

export function throwIfReplyError(reply: FrameReply): void {
  const error = errorFromReply(reply);
  if (error) {
    throw error;
  }
}
