export type {
  Bridge,
  ClientOptions,
  CommandOptions,
  DoctorStatus,
  HoldResult,
  RawStream,
  SplitCommandOptions,
  TerminalCommandOptions,
  TerminalOptions,
} from "./client.js";
export { client, GhosttyKitClient } from "./client.js";
export {
  errorFromReply,
  GhosttyKitError,
  GhosttyUnavailableError,
  InternalError,
  InvalidReplyError,
  InvalidReplyModeError,
  InvalidRequestError,
  PasteConsumedError,
  PasteEmptyError,
  PasteUnsupportedError,
  ProtocolVersionMismatchError,
  ReplyError,
  StreamFailedError,
  TerminalNotFoundError,
  TransportError,
  throwIfReplyError,
  UnknownCommandError,
} from "./errors.js";
export type {
  FilesPaste,
  PasteFile,
  PasteFileContent,
  PasteMatcher,
  PasteState,
  SavedPasteFile,
  TextPaste,
} from "./paste.js";
export { Paste } from "./paste.js";
export type {
  Direction,
  FocusTarget,
  ResizeAmount,
} from "./protocol.js";
export * as protocol from "./protocol.js";
export { defaultSocketPath, dial, socketPath } from "./socket.js";
