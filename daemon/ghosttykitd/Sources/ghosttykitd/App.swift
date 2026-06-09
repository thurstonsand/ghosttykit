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
        version: "ghosttykitd \(GhosttyKitVersion.current)"
    )

    @Flag(help: "Run without calling Ghostty AppleScript APIs.")
    var dryRun = false

    mutating func run() async throws {
        let options = DaemonOptions(dryRun: dryRun, socketPath: daemonSocketPath())
        let daemon = GhosttyKitDaemon(options: options)
        try await daemon.start()
    }
}

enum GhosttyKitVersion {
    static var current: String {
        bundledVersion ?? "0.0.0-dev"
    }

    private static var bundledVersion: String? {
        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            return version
        }

        guard let executableURL = Bundle.main.executableURL?.resolvingSymlinksInPath() else {
            return nil
        }

        let infoURL = executableURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Info.plist")

        guard
            let data = try? Data(contentsOf: infoURL),
            let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
            let dictionary = plist as? [String: Any]
        else {
            return nil
        }

        return dictionary["CFBundleShortVersionString"] as? String
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
        preflightAutomationPermission()
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

    private func preflightAutomationPermission() {
        do {
            if try ghostty.preflightAutomationPermission() {
                logger.ghosttykit("automation preflight completed")
            } else {
                logger.ghosttykit("automation preflight skipped reason=ghostty_not_running")
            }
        } catch {
            logger.ghosttykit("automation preflight failed error=\(error.localizedDescription)")
        }
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
