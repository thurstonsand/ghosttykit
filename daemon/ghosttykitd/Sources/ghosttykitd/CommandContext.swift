import Foundation
import OSLog

protocol CommandContext: AnyObject {
    var cache: TerminalIDCache { get }
    var ghostty: GhosttyControlling { get }
    var logger: Logger { get }
    var spawnRendezvous: SpawnRendezvous { get }
    var spawnWrapper: SpawnWrapper? { get }

    func terminal(for tty: String) throws -> TerminalContext
    func recoverTerminalBinding(for tty: String) -> Bool
}

final class MainCommandContext: CommandContext {
    let cache: TerminalIDCache
    let ghostty: GhosttyControlling
    let logger: Logger
    let spawnRendezvous: SpawnRendezvous
    let spawnWrapper: SpawnWrapper?
    private let bridgeManager: BridgeSessionManaging

    init(
        cache: TerminalIDCache,
        ghostty: GhosttyControlling,
        logger: Logger,
        bridgeManager: BridgeSessionManaging,
        spawnRendezvous: SpawnRendezvous,
        spawnWrapper: SpawnWrapper?
    ) {
        self.cache = cache
        self.ghostty = ghostty
        self.logger = logger
        self.bridgeManager = bridgeManager
        self.spawnRendezvous = spawnRendezvous
        self.spawnWrapper = spawnWrapper
    }

    func terminal(for tty: String) throws -> TerminalContext {
        if let terminal = cache.terminal(for: tty) {
            return terminal
        }
        let terminal = try ghostty.terminalContext(forTTY: tty)
        cache.store(terminal: terminal, for: tty)
        return terminal
    }

    func recoverTerminalBinding(for tty: String) -> Bool {
        cache.clear(tty: tty)
        return true
    }

    func createBridge(terminal: TerminalContext) throws -> BridgeCreateReply {
        try bridgeManager.createBridge(terminal: terminal)
    }

    func claimSpawn(token: String, tty: String) throws -> TerminalContext {
        guard let terminal = spawnRendezvous.claim(token: token, tty: tty) else {
            throw SpawnClaimError.tokenNotFound(token)
        }
        cache.store(terminal: terminal, for: tty)
        return terminal
    }
}

final class BridgeCommandContext: CommandContext {
    let cache: TerminalIDCache
    let ghostty: GhosttyControlling
    let logger: Logger
    let spawnRendezvous: SpawnRendezvous
    let spawnWrapper: SpawnWrapper?
    private let bridgeTerminal: TerminalContext
    private let lease: BridgeLease

    init(
        cache: TerminalIDCache,
        ghostty: GhosttyControlling,
        logger: Logger,
        terminal: TerminalContext,
        lease: BridgeLease,
        spawnRendezvous: SpawnRendezvous,
        spawnWrapper: SpawnWrapper?
    ) {
        self.cache = cache
        self.ghostty = ghostty
        self.logger = logger
        bridgeTerminal = terminal
        self.lease = lease
        self.spawnRendezvous = spawnRendezvous
        self.spawnWrapper = spawnWrapper
    }

    func terminal(for _: String) throws -> TerminalContext {
        bridgeTerminal
    }

    func recoverTerminalBinding(for _: String) -> Bool {
        false
    }

    func acceptHold(token: String) throws -> ConnectionHold {
        try lease.accept(token: token)
    }
}
