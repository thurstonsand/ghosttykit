import Foundation
import OSLog

protocol BridgeSessionManaging: AnyObject {
    func createBridge(terminal: TerminalContext) throws -> BridgeCreateReply
}

final class BridgeSessionManager: BridgeSessionManaging {
    typealias RequestHandler = @Sendable (TerminalContext, BridgeLease, any CommandRequest) -> CommandResult

    private let logger: Logger
    private let rootDirectory: URL
    private let requestHandler: RequestHandler
    private var sessions: [String: BridgeSession] = [:]
    private let lock = NSLock()

    init(
        logger: Logger,
        rootDirectory: URL = defaultBridgeRootDirectory(),
        requestHandler: @escaping RequestHandler
    ) {
        self.logger = logger
        self.rootDirectory = rootDirectory
        self.requestHandler = requestHandler
    }

    func createBridge(terminal: TerminalContext) throws -> BridgeCreateReply {
        try FileManager.default.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
        chmod(rootDirectory.path, 0o700)

        let sessionID = UUID().uuidString.lowercased()
        let socketPath = rootDirectory.appendingPathComponent("bridge-\(sessionID).sock").path
        let leaseToken = UUID().uuidString
        let session = BridgeSession(
            id: sessionID,
            socketPath: socketPath,
            leaseToken: leaseToken,
            terminal: terminal,
            logger: logger,
            requestHandler: requestHandler
        ) { [weak self] id in
            self?.removeSession(id: id)
        }

        lock.withLock { sessions[sessionID] = session }
        do {
            try session.start()
        } catch {
            removeSession(id: sessionID)
            throw error
        }

        logger.ghosttykit("bridge created id=\(sessionID) socket=\(socketPath) terminal=\(terminal.terminalID)")
        return BridgeCreateReply.ok(socketPath: socketPath, leaseToken: leaseToken)
    }

    private func removeSession(id: String) {
        let session = lock.withLock { sessions.removeValue(forKey: id) }
        session?.stop()
    }
}

final class BridgeSession {
    private let id: String
    private let socketPath: String
    private let terminal: TerminalContext
    private let logger: Logger
    private let requestHandler: BridgeSessionManager.RequestHandler
    private let onClose: @Sendable (String) -> Void
    private let lease: BridgeLease
    private var daemon: UnixSocketDaemon?
    private var daemonTask: Task<Void, Error>?

    init(
        id: String,
        socketPath: String,
        leaseToken: String,
        terminal: TerminalContext,
        logger: Logger,
        requestHandler: @escaping BridgeSessionManager.RequestHandler,
        onClose: @escaping @Sendable (String) -> Void
    ) {
        self.id = id
        self.socketPath = socketPath
        self.terminal = terminal
        self.logger = logger
        self.requestHandler = requestHandler
        self.onClose = onClose
        lease = BridgeLease(token: leaseToken) { onClose(id) }
    }

    func start() throws {
        let daemon = UnixSocketDaemon(socketPath: socketPath, logger: logger) { [weak self] request in
            guard let self else {
                return .reply(.frame(FrameReply.failure(code: ProtocolCode.internalError, "bridge unavailable")))
            }
            guard request is BridgeLeaseRequest || lease.isActive else {
                return .reply(.frame(FrameReply.failure(
                    code: ProtocolCode.invalidRequest,
                    "bridge lease is not active"
                )))
            }
            return requestHandler(terminal, lease, request)
        }
        daemonTask = try daemon.startDetached()
        self.daemon = daemon
    }

    func stop() {
        daemonTask?.cancel()
        daemonTask = nil
        daemon?.stop()
        daemon = nil
        logger.ghosttykit("bridge destroyed id=\(id) socket=\(socketPath)")
    }
}

final class BridgeLease: @unchecked Sendable {
    // Safe to share across tasks because all mutable lease state is serialized by lock.
    private let token: String
    private let onRelease: @Sendable () -> Void
    private let lock = NSLock()
    private var active = false
    private var released = false

    init(token: String, onRelease: @escaping @Sendable () -> Void) {
        self.token = token
        self.onRelease = onRelease
    }

    var isActive: Bool {
        lock.withLock { active && !released }
    }

    func accept(token: String) throws -> ConnectionHold {
        try lock.withLock {
            guard token == self.token else {
                throw RequestValidationError.invalidRequest("bridge lease rejected")
            }
            guard !active, !released else {
                throw RequestValidationError.invalidRequest("bridge lease rejected")
            }
            active = true
            return ConnectionHold { [weak self] in self?.release() }
        }
    }

    private func release() {
        let shouldRelease = lock.withLock { () -> Bool in
            guard !released else { return false }
            released = true
            active = false
            return true
        }
        if shouldRelease {
            onRelease()
        }
    }
}

func defaultBridgeRootDirectory() -> URL {
    FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/run/ghosttykit/bridges")
}
