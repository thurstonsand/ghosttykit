import Foundation
import OSLog

enum SpawnClaimError: Error, LocalizedError {
    case tokenNotFound(String)

    var errorDescription: String? {
        switch self {
        case let .tokenNotFound(token): "no pending spawn matches token \(token)"
        }
    }

    var protocolCode: String {
        ProtocolCode.spawnTokenNotFound
    }
}

/// Holds pending daemon-spawned terminals between mint and claim. Not a cache: entries own
/// connection state (a parked split reply) and live only for the spawn window.
final class SpawnRendezvous {
    static let spawnTimeout: TimeInterval = 5

    private struct PendingSpawn {
        let terminal: TerminalContext
        var waiter: ((String?) -> Void)?
    }

    private let lock = NSLock()
    private var pending: [String: PendingSpawn] = [:]
    private let logger: Logger
    private let timeout: TimeInterval
    private let sweepQueue = DispatchQueue(label: "ghosttykitd.spawn-rendezvous")

    init(logger: Logger, timeout: TimeInterval = SpawnRendezvous.spawnTimeout) {
        self.logger = logger
        self.timeout = timeout
    }

    /// Deposits the terminal under its minted token, claimable until the sweep deadline.
    func escrow(token: String, terminal: TerminalContext) {
        lock.withLock { pending[token] = PendingSpawn(terminal: terminal, waiter: nil) }
        logger.ghosttykit("escrowed spawn terminal terminal_id=\(terminal.terminalID)")
        sweepQueue.asyncAfter(deadline: .now() + timeout) { [weak self] in
            self?.sweep(token: token)
        }
    }

    func claim(token: String, tty: String) -> TerminalContext? {
        guard let entry = lock.withLock({ pending.removeValue(forKey: token) }) else {
            return nil
        }
        entry.waiter?(tty)
        return entry.terminal
    }

    /// Parks a waiter that receives the claimed tty, or nil when the token is unknown or swept.
    func park(token: String, waiter: @escaping (String?) -> Void) {
        let accepted = lock.withLock { () -> Bool in
            guard var entry = pending[token] else { return false }
            entry.waiter = waiter
            pending[token] = entry
            return true
        }
        if !accepted {
            waiter(nil)
        }
    }

    private func sweep(token: String) {
        guard let entry = lock.withLock({ pending.removeValue(forKey: token) }) else { return }
        entry.waiter?(nil)
        logger.ghosttykit("swept unclaimed spawn token terminal_id=\(entry.terminal.terminalID)")
    }
}
