export const protocolCodes = {
  ok: "ok",
  protocolVersionMismatch: "protocol_version_mismatch",
  unknownCommand: "unknown_command",
  invalidRequest: "invalid_request",
  terminalNotFound: "terminal_not_found",
  ghosttyUnavailable: "ghostty_unavailable",
  pasteEmpty: "paste_empty",
  pasteUnsupported: "paste_unsupported",
  streamFailed: "stream_failed",
  internalError: "internal_error",
} as const;

export type ProtocolCode = (typeof protocolCodes)[keyof typeof protocolCodes];
