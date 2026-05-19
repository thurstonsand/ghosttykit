import AppKit
import ArgumentParser
import Foundation
import OSLog

struct DaemonOptions {
    let dryRun: Bool
    let socketPath: String
}

@main
struct GhosttyKitDaemonCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ghosttykitd",
        abstract: "GhosttyKit macOS daemon.",
        version: "ghosttykitd 0.0.0-dev"
    )

    @Flag(help: "Run without calling Ghostty AppleScript APIs.")
    var dryRun = false

    mutating func run() async throws {
        let options = DaemonOptions(dryRun: dryRun, socketPath: daemonSocketPath())
        let daemon = GhosttyKitDaemon(options: options)
        try await daemon.start()
    }
}

final class GhosttyKitDaemon {
    private let logger = Logger(subsystem: "dev.ghosttykit.ghosttykitd", category: "daemon")
    private let options: DaemonOptions
    private let ghostty: GhosttyControlling
    private lazy var cache = TerminalIDCache(logger: logger)
    private lazy var bridgeManager = BridgeSessionManager(logger: logger) { [weak self] terminal, lease, request in
        guard let self else {
            return .reply(.frame(FrameReply.failure(code: ProtocolCode.internalError, "daemon unavailable")))
        }
        let context = BridgeCommandContext(
            cache: cache,
            ghostty: ghostty,
            logger: logger,
            terminal: terminal,
            lease: lease
        )
        return commandQueue.sync { self.dispatch(request, using: context) }
    }

    private let commandQueue = DispatchQueue(label: "ghosttykitd.commands")

    init(options: DaemonOptions) {
        self.options = options
        ghostty = options.dryRun
            ? DryRunGhosttyController(pasteText: ProcessInfo.processInfo.environment["GTY_DRY_RUN_PASTE_TEXT"])
            : AppleScriptGhosttyController()
    }

    func start() async throws {
        await MainActor.run { _ = NSApplication.shared }
        logger.ghosttykit("starting dry_run=\(options.dryRun) socket=\(options.socketPath)")
        let daemon = UnixSocketDaemon(socketPath: options.socketPath, logger: logger) { [weak self] request in
            guard let self else {
                return .reply(.frame(FrameReply.failure(code: ProtocolCode.internalError, "daemon unavailable")))
            }
            let context = MainCommandContext(
                cache: cache,
                ghostty: ghostty,
                logger: logger,
                bridgeManager: bridgeManager
            )
            return commandQueue.sync { self.dispatch(request, using: context) }
        }
        try await daemon.start()
    }

    private func dispatch(_ request: any CommandRequest, using context: CommandContext) -> CommandResult {
        switch request.replyMode {
        case .none:
            Task { _ = request.commandReply(using: context) }
            return .none
        case .frame, .stream:
            return request.dispatch(using: context)
        }
    }
}

private func daemonSocketPath() -> String {
    if let value = ProcessInfo.processInfo.environment["GTY_SOCK"], !value.isEmpty {
        return value
    }
    return FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/run/ghosttykit/ghosttykitd.sock")
        .path
}
