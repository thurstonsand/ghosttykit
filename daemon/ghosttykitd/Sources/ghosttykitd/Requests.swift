import Foundation
import OSLog

enum ProtocolVersion {
    static let current = 1
}

@propertyWrapper
struct DefaultFalse: Decodable {
    var wrappedValue = false

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        wrappedValue = try container.decode(Bool.self)
    }
}

extension KeyedDecodingContainer {
    func decode(_ type: DefaultFalse.Type, forKey key: Key) throws -> DefaultFalse {
        try decodeIfPresent(type, forKey: key) ?? DefaultFalse()
    }
}

enum ProtocolCode {
    static let ok = "ok"
    static let protocolVersionMismatch = "protocol_version_mismatch"
    static let unknownCommand = "unknown_command"
    static let invalidRequest = "invalid_request"
    static let terminalNotFound = "terminal_not_found"
    static let spawnTokenNotFound = "spawn_token_not_found"
    static let ghosttyUnavailable = "ghostty_unavailable"
    static let pasteEmpty = "paste_empty"
    static let pasteUnsupported = "paste_unsupported"
    static let streamFailed = "stream_failed"
    static let internalError = "internal_error"
}

enum ReplyMode {
    case frame
    case none
    case stream
}

enum CommandResult {
    case none
    case reply(ReplyBody)
    case hold(HoldReplyBody)
    /// The reply is not ready at dispatch time; the connection awaits it off the command queue.
    case deferred(@Sendable () async -> ReplyBody)
}

enum ReplyBody {
    case frame(any Encodable)
    case stream(FrameStreamReply)
}

struct HoldReplyBody {
    let frame: any Encodable
    let hold: ConnectionHold
}

struct ConnectionHold {
    private let releaseHandler: @Sendable () -> Void

    init(release: @escaping @Sendable () -> Void) {
        releaseHandler = release
    }

    func release() {
        releaseHandler()
    }
}

protocol CommandRequest: Decodable {
    var version: Int { get }
    var command: String { get }
    var tty: String? { get }
    var replyMode: ReplyMode { get }
    func dispatch(using context: CommandContext) -> CommandResult
    func reply(using context: CommandContext) throws -> ReplyBody
    func errorReply(for error: Error) -> ReplyBody
}

extension CommandRequest {
    var replyMode: ReplyMode {
        .frame
    }

    func dispatch(using context: CommandContext) -> CommandResult {
        .reply(commandReply(using: context))
    }

    func commandReply(using context: CommandContext) -> ReplyBody {
        do {
            return try reply(using: context)
        } catch {
            context.cache.clear(tty: tty)
            context.logger.ghosttykit("\(logSummary) failed error=\(error.localizedDescription)")
            return errorReply(for: error)
        }
    }

    func errorReply(for error: Error) -> ReplyBody {
        .frame(responseForError(error))
    }

    var logSummary: String {
        var parts = ["command=\(command)"]
        if let tty { parts.append("tty=\(tty)") }
        return parts.joined(separator: " ")
    }
}

protocol AckCommandRequest: CommandRequest {
    var ack: Bool { get }
}

extension AckCommandRequest {
    var replyMode: ReplyMode {
        ack ? .frame : .none
    }
}

protocol TerminalCommandRequest: CommandRequest {
    var rawTTY: String { get }
    var focused: Bool { get }
}

extension TerminalCommandRequest {
    var tty: String? {
        normalizeTTY(rawTTY)
    }

    func terminal(using context: CommandContext) throws -> TerminalContext {
        try context.terminal(for: normalizeTTY(rawTTY), focused: focused)
    }
}

struct FrameEnvelope: Decodable {
    let version: Int
    let command: String
}

struct ResizeAmount: Decodable {
    let pixels: Int?
    let percent: Double?
}

struct TerminalIDRequest: CommandRequest {
    let version: Int
    let command: String
    let rawTTY: String?
    @DefaultFalse var focused: Bool
    @DefaultFalse var refresh: Bool

    enum CodingKeys: String, CodingKey {
        case version
        case command
        case rawTTY = "tty"
        case focused
        case refresh
    }

    var tty: String? {
        rawTTY.map(normalizeTTY)
    }

    func reply(using context: CommandContext) throws -> ReplyBody {
        let terminal = try terminal(using: context)
        return .frame(FrameReply.ok(terminal.terminalID))
    }

    private func terminal(using context: CommandContext) throws -> TerminalContext {
        switch (refresh, tty, focused) {
        case (true, .some, false):
            throw RequestValidationError.invalidRequest(
                "cannot refresh terminal-id if it is not the focused window"
            )
        case (true, let tty?, true):
            let terminal = try context.ghostty.focusedTerminalContext()
            context.cache.store(terminal: terminal, for: tty)
            return terminal
        case (true, nil, _):
            return try context.ghostty.focusedTerminalContext()
        case (false, let tty?, let focused):
            return try context.terminal(for: tty, focused: focused)
        case (false, nil, _):
            return try context.ghostty.focusedTerminalContext()
        }
    }
}

struct TabTerminalCountRequest: CommandRequest {
    let version: Int
    let command: String
    let rawTTY: String?
    @DefaultFalse var focused: Bool

    enum CodingKeys: String, CodingKey {
        case version
        case command
        case rawTTY = "tty"
        case focused
    }

    var tty: String? {
        rawTTY.map(normalizeTTY)
    }

    func reply(using context: CommandContext) throws -> ReplyBody {
        let terminal = try tty.map { try context.terminal(for: $0, focused: focused) }
        let count = try context.ghostty.tabTerminalCount(terminal: terminal)
        return .frame(FrameReply.ok(String(count)))
    }
}

struct ClearCacheRequest: AckCommandRequest {
    let version: Int
    let command: String
    let rawTTY: String?
    @DefaultFalse var ack: Bool

    enum CodingKeys: String, CodingKey {
        case version
        case command
        case rawTTY = "tty"
        case ack
    }

    var tty: String? {
        rawTTY.map(normalizeTTY)
    }

    var logSummary: String {
        if tty == nil { return "command=\(command) scope=all" }
        return "command=\(command) tty=\(tty ?? "")"
    }

    func reply(using context: CommandContext) throws -> ReplyBody {
        context.cache.clear(tty: tty)
        return .frame(FrameReply.ok())
    }
}

struct KeyTableActivateRequest: TerminalCommandRequest, AckCommandRequest {
    let version: Int
    let command: String
    let rawTTY: String
    @DefaultFalse var focused: Bool
    let table: String
    @DefaultFalse var ack: Bool

    enum CodingKeys: String, CodingKey {
        case version
        case command
        case rawTTY = "tty"
        case focused
        case table
        case ack
    }

    var logSummary: String {
        "command=\(command) tty=\(tty ?? "") table=\(table)"
    }

    func reply(using context: CommandContext) throws -> ReplyBody {
        try context.ghostty.activateKeyTable(table, terminal: terminal(using: context))
        return .frame(FrameReply.ok())
    }
}

struct KeyTableDeactivateRequest: TerminalCommandRequest, AckCommandRequest {
    let version: Int
    let command: String
    let rawTTY: String
    @DefaultFalse var focused: Bool
    @DefaultFalse var ack: Bool

    enum CodingKeys: String, CodingKey {
        case version
        case command
        case rawTTY = "tty"
        case focused
        case ack
    }

    func reply(using context: CommandContext) throws -> ReplyBody {
        try context.ghostty.deactivateKeyTable(terminal: terminal(using: context))
        return .frame(FrameReply.ok())
    }
}

struct FocusRequest: TerminalCommandRequest, AckCommandRequest {
    let version: Int
    let command: String
    let rawTTY: String
    @DefaultFalse var focused: Bool
    let direction: Direction
    @DefaultFalse var ack: Bool

    enum CodingKeys: String, CodingKey {
        case version
        case command
        case rawTTY = "tty"
        case focused
        case direction
        case ack
    }

    var logSummary: String {
        "command=\(command) tty=\(tty ?? "") direction=\(direction)"
    }

    func reply(using context: CommandContext) throws -> ReplyBody {
        try context.ghostty.focusSplit(direction: direction, terminal: terminal(using: context))
        return .frame(FrameReply.ok())
    }
}

struct SplitRequest: TerminalCommandRequest, AckCommandRequest {
    let version: Int
    let command: String
    let rawTTY: String
    @DefaultFalse var focused: Bool
    let direction: Direction
    let cwd: String?
    let commandText: String?
    let focus: FocusTarget?
    @DefaultFalse var ack: Bool

    enum CodingKeys: String, CodingKey {
        case version
        case command
        case rawTTY = "tty"
        case focused
        case direction
        case cwd
        case commandText
        case focus
        case ack
    }

    var logSummary: String {
        "command=\(command) tty=\(tty ?? "") direction=\(direction)"
    }

    /// Only reached when ack is true: parks the reply on the spawn rendezvous so it can carry the
    /// claimed tty. The wait happens off the command queue — the claim it waits for dispatches there.
    func dispatch(using context: CommandContext) -> CommandResult {
        do {
            guard let token = try performSplit(using: context) else {
                return .reply(.frame(FrameReply.ok()))
            }
            let (claims, continuation) = AsyncStream<String?>.makeStream()
            context.spawnRendezvous.park(token: token) { tty in
                continuation.yield(tty)
                continuation.finish()
            }
            return .deferred {
                var claimed: String?
                for await tty in claims {
                    claimed = tty
                }
                return .frame(FrameReply.ok(claimed))
            }
        } catch {
            context.cache.clear(tty: tty)
            context.logger.ghosttykit("\(logSummary) failed error=\(error.localizedDescription)")
            return .reply(errorReply(for: error))
        }
    }

    func reply(using context: CommandContext) throws -> ReplyBody {
        _ = try performSplit(using: context)
        return .frame(FrameReply.ok())
    }

    private func performSplit(using context: CommandContext) throws -> String? {
        let origin = try terminal(using: context)
        let spawn = context.spawnWrapper?.mint(wrapping: commandText)
        let newTerminal = try context.ghostty.split(
            direction: direction,
            cwd: cwd,
            command: spawn?.command ?? commandText,
            focus: focus ?? .new,
            terminal: origin
        )
        if let spawn {
            context.spawnRendezvous.escrow(token: spawn.token, terminal: newTerminal)
        }
        return spawn?.token
    }
}

struct InputRequest: TerminalCommandRequest, AckCommandRequest {
    let version: Int
    let command: String
    let rawTTY: String
    @DefaultFalse var focused: Bool
    let text: String
    @DefaultFalse var submit: Bool
    @DefaultFalse var ack: Bool

    enum CodingKeys: String, CodingKey {
        case version
        case command
        case rawTTY = "tty"
        case focused
        case text
        case submit
        case ack
    }

    /// The text stays out of logs deliberately.
    var logSummary: String {
        "command=\(command) tty=\(tty ?? "") submit=\(submit)"
    }

    func reply(using context: CommandContext) throws -> ReplyBody {
        try context.ghostty.input(text, submit: submit, terminal: terminal(using: context))
        return .frame(FrameReply.ok())
    }
}

struct ResizeCommandRequest: TerminalCommandRequest, AckCommandRequest {
    let version: Int
    let command: String
    let rawTTY: String
    @DefaultFalse var focused: Bool
    let direction: Direction
    let amount: ResizeAmount
    @DefaultFalse var ack: Bool

    enum CodingKeys: String, CodingKey {
        case version
        case command
        case rawTTY = "tty"
        case focused
        case direction
        case amount
        case ack
    }

    var logSummary: String {
        "command=\(command) tty=\(tty ?? "") direction=\(direction)"
    }

    func reply(using context: CommandContext) throws -> ReplyBody {
        try context.ghostty.resize(
            direction: direction, amount: amount, terminal: terminal(using: context)
        )
        return .frame(FrameReply.ok())
    }
}

struct ZoomRequest: TerminalCommandRequest, AckCommandRequest {
    let version: Int
    let command: String
    let rawTTY: String
    @DefaultFalse var focused: Bool
    @DefaultFalse var ack: Bool

    enum CodingKeys: String, CodingKey {
        case version
        case command
        case rawTTY = "tty"
        case focused
        case ack
    }

    func reply(using context: CommandContext) throws -> ReplyBody {
        try context.ghostty.toggleSplitZoom(terminal: terminal(using: context))
        return .frame(FrameReply.ok())
    }
}

struct CreateBridgeRequest: TerminalCommandRequest {
    let version: Int
    let command: String
    let rawTTY: String
    @DefaultFalse var focused: Bool

    enum CodingKeys: String, CodingKey {
        case version
        case command
        case rawTTY = "tty"
        case focused
    }

    var logSummary: String {
        "command=\(command) tty=\(tty ?? "")"
    }

    func reply(using context: CommandContext) throws -> ReplyBody {
        guard let context = context as? MainCommandContext else {
            throw RequestValidationError.invalidRequest("bridge creation is not accepted by this endpoint")
        }
        return try .frame(context.createBridge(terminal: terminal(using: context)))
    }
}

struct SpawnClaimRequest: CommandRequest {
    let version: Int
    let command: String
    let rawTTY: String
    let spawnToken: String

    enum CodingKeys: String, CodingKey {
        case version
        case command
        case rawTTY = "tty"
        case spawnToken
    }

    var tty: String? {
        normalizeTTY(rawTTY)
    }

    /// Skips commandReply: a failed claim must leave the tty's existing cache entry untouched.
    func dispatch(using context: CommandContext) -> CommandResult {
        do {
            return try .reply(reply(using: context))
        } catch {
            context.logger.ghosttykit("\(logSummary) failed error=\(error.localizedDescription)")
            return .reply(errorReply(for: error))
        }
    }

    func reply(using context: CommandContext) throws -> ReplyBody {
        guard let context = context as? MainCommandContext else {
            throw RequestValidationError.invalidRequest("spawn claims are not accepted by this endpoint")
        }
        _ = try context.claimSpawn(token: spawnToken, tty: normalizeTTY(rawTTY))
        return .frame(FrameReply.ok())
    }
}

struct BridgeLeaseRequest: CommandRequest {
    let version: Int
    let command: String
    let token: String

    var tty: String? {
        nil
    }

    func dispatch(using context: CommandContext) -> CommandResult {
        do {
            guard let context = context as? BridgeCommandContext else {
                throw RequestValidationError.invalidRequest("hold is not accepted by this endpoint")
            }
            return try .hold(HoldReplyBody(frame: FrameReply.ok(), hold: context.acceptHold(token: token)))
        } catch {
            context.logger.ghosttykit("\(logSummary) failed error=\(error.localizedDescription)")
            return .reply(errorReply(for: error))
        }
    }

    func reply(using context: CommandContext) throws -> ReplyBody {
        .frame(FrameReply.ok())
    }
}

struct PasteRequest: CommandRequest {
    let version: Int
    let command: String
    let rawTTY: String?

    enum CodingKeys: String, CodingKey {
        case version
        case command
        case rawTTY = "tty"
    }

    var tty: String? {
        rawTTY.map(normalizeTTY)
    }

    var replyMode: ReplyMode {
        .stream
    }

    func reply(using context: CommandContext) throws -> ReplyBody {
        try .stream(context.ghostty.readPasteboardContent())
    }

    func errorReply(for error: Error) -> ReplyBody {
        .stream(FrameStreamReply(header: pasteFrameFailure(for: error), streams: []))
    }
}

private func pasteFrameFailure(for error: Error) -> PasteStreamFrameHeader {
    if let pasteboardError = error as? PasteboardError {
        return .failure(code: pasteboardError.protocolCode, error.localizedDescription)
    }
    let response = responseForError(error)
    return .failure(code: response.code, response.error ?? "request failed")
}

func decodeCommand(from data: Data) throws -> any CommandRequest {
    let trimmed = linePayload(from: data)
    let envelope = try JSONDecoder().decode(FrameEnvelope.self, from: trimmed)
    guard envelope.version == ProtocolVersion.current else {
        throw RequestDecodeError.protocolVersionMismatch(envelope.version)
    }
    guard let decode = commandDecoders[envelope.command] else {
        throw RequestDecodeError.unknownCommand(envelope.command)
    }
    return try decode(trimmed)
}

func responseForError(_ error: Error) -> FrameReply {
    let message = error.localizedDescription
    switch error {
    case let requestError as RequestDecodeError:
        return .failure(code: requestError.protocolCode, message)
    case let decodingError as DecodingError:
        return .failure(code: ProtocolCode.invalidRequest, decodingErrorMessage(decodingError))
    case let validationError as RequestValidationError:
        return .failure(code: validationError.protocolCode, message)
    case let claimError as SpawnClaimError:
        return .failure(code: claimError.protocolCode, message)
    case let ghosttyError as GhosttyKitError:
        return .failure(code: ghosttyError.protocolCode, message)
    case let pasteboardError as PasteboardError:
        return .failure(code: pasteboardError.protocolCode, message)
    default:
        return .failure(code: ProtocolCode.ghosttyUnavailable, message)
    }
}

private func decodingErrorMessage(_ error: DecodingError) -> String {
    switch error {
    case let .keyNotFound(key, _):
        return "missing required field: \(key.stringValue)"
    case let .typeMismatch(type, _):
        return "invalid field type: expected \(type)"
    case let .valueNotFound(type, _):
        return "missing required value: \(type)"
    case let .dataCorrupted(context):
        return context.debugDescription
    @unknown default:
        return "invalid request"
    }
}

enum RequestValidationError: Error, LocalizedError {
    case invalidRequest(String)

    var errorDescription: String? {
        switch self {
        case let .invalidRequest(message): message
        }
    }

    var protocolCode: String {
        ProtocolCode.invalidRequest
    }
}

private enum RequestDecodeError: Error, LocalizedError {
    case protocolVersionMismatch(Int)
    case unknownCommand(String)

    var errorDescription: String? {
        switch self {
        case let .protocolVersionMismatch(version): "unsupported protocol version: \(version)"
        case let .unknownCommand(command): "unknown command: \(command)"
        }
    }

    var protocolCode: String {
        switch self {
        case .protocolVersionMismatch: ProtocolCode.protocolVersionMismatch
        case .unknownCommand: ProtocolCode.unknownCommand
        }
    }
}

private let commandDecoders: [String: (Data) throws -> any CommandRequest] = [
    "doctor": { try JSONDecoder().decode(DoctorRequest.self, from: $0) },
    "terminal-id": { try JSONDecoder().decode(TerminalIDRequest.self, from: $0) },
    "tab-terminal-count": { try JSONDecoder().decode(TabTerminalCountRequest.self, from: $0) },
    "clear-cache": { try JSONDecoder().decode(ClearCacheRequest.self, from: $0) },
    "bridge-create": { try JSONDecoder().decode(CreateBridgeRequest.self, from: $0) },
    "bridge-lease": { try JSONDecoder().decode(BridgeLeaseRequest.self, from: $0) },
    "spawn-claim": { try JSONDecoder().decode(SpawnClaimRequest.self, from: $0) },
    "key-table-activate": { try JSONDecoder().decode(KeyTableActivateRequest.self, from: $0) },
    "key-table-deactivate": { try JSONDecoder().decode(KeyTableDeactivateRequest.self, from: $0) },
    "focus": { try JSONDecoder().decode(FocusRequest.self, from: $0) },
    "split": { try JSONDecoder().decode(SplitRequest.self, from: $0) },
    "input": { try JSONDecoder().decode(InputRequest.self, from: $0) },
    "resize": { try JSONDecoder().decode(ResizeCommandRequest.self, from: $0) },
    "zoom": { try JSONDecoder().decode(ZoomRequest.self, from: $0) },
    "paste": { try JSONDecoder().decode(PasteRequest.self, from: $0) }
]

private func linePayload(from data: Data) -> Data {
    if let newline = data.firstIndex(of: 0x0A) {
        return Data(data[..<newline])
    }
    return data
}
