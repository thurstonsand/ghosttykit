import Foundation
import OSLog

protocol CommandContext: AnyObject {
    var cache: TerminalIDCache { get }
    var ghostty: GhosttyControlling { get }
    var logger: Logger { get }

    func terminal(explicitTTY: String?, callerTTY: String?) throws -> TerminalContext
    func clearBinding(explicitTTY: String?, callerTTY: String?) throws
}

extension CommandContext {
    /// A cached binding is used only after Ghostty confirms it: a closed terminal's pty is reused
    /// by the next one, and a terminal can move to another tab or window.
    func boundTerminal(tty: String) throws -> TerminalContext {
        if let terminal = cache.terminal(for: tty), try ghostty.isBound(terminal, to: tty) {
            return terminal
        }
        let terminal = try ghostty.terminalContext(forTTY: tty)
        cache.store(terminal: terminal, for: tty)
        return terminal
    }
}

final class MainCommandContext: CommandContext {
    let cache: TerminalIDCache
    let ghostty: GhosttyControlling
    let logger: Logger
    private let bridgeManager: BridgeSessionManaging

    init(
        cache: TerminalIDCache,
        ghostty: GhosttyControlling,
        logger: Logger,
        bridgeManager: BridgeSessionManaging
    ) {
        self.cache = cache
        self.ghostty = ghostty
        self.logger = logger
        self.bridgeManager = bridgeManager
    }

    /// An explicit target wins over the caller's own terminal.
    func terminal(explicitTTY: String?, callerTTY: String?) throws -> TerminalContext {
        try boundTerminal(tty: target(explicitTTY: explicitTTY, callerTTY: callerTTY))
    }

    func clearBinding(explicitTTY: String?, callerTTY: String?) throws {
        try cache.clear(tty: target(explicitTTY: explicitTTY, callerTTY: callerTTY))
    }

    func createBridge(explicitTTY: String?, callerTTY: String?) throws -> BridgeCreateReply {
        let tty = try target(explicitTTY: explicitTTY, callerTTY: callerTTY)
        _ = try boundTerminal(tty: tty)
        return try bridgeManager.createBridge(tty: tty)
    }

    private func target(explicitTTY: String?, callerTTY: String?) throws -> String {
        guard let tty = explicitTTY ?? callerTTY else {
            throw RequestValidationError.invalidRequest(
                "request names no terminal: pass tty, or run from a terminal so the client sends callerTty"
            )
        }
        return tty
    }
}

final class BridgeCommandContext: CommandContext {
    let cache: TerminalIDCache
    let ghostty: GhosttyControlling
    let logger: Logger
    private let bridgeTTY: String
    private let lease: BridgeLease

    init(
        cache: TerminalIDCache,
        ghostty: GhosttyControlling,
        logger: Logger,
        tty: String,
        lease: BridgeLease
    ) {
        self.cache = cache
        self.ghostty = ghostty
        self.logger = logger
        bridgeTTY = tty
        self.lease = lease
    }

    /// The caller's tty names a terminal on the remote host, so only the bridge's own local tty
    /// counts. That pty stays open as long as the `gty ssh` holding the lease runs in it.
    func terminal(explicitTTY: String?, callerTTY _: String?) throws -> TerminalContext {
        try rejectExplicitTarget(explicitTTY)
        return try boundTerminal(tty: bridgeTTY)
    }

    func clearBinding(explicitTTY: String?, callerTTY _: String?) throws {
        try rejectExplicitTarget(explicitTTY)
        cache.clear(tty: bridgeTTY)
    }

    func acceptHold(token: String) throws -> ConnectionHold {
        try lease.accept(token: token)
    }

    private func rejectExplicitTarget(_ explicitTTY: String?) throws {
        if explicitTTY != nil {
            throw RequestValidationError.invalidRequest(
                "a bridge acts only on the terminal that created it and does not accept tty"
            )
        }
    }
}
