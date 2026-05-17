import Foundation
import OSLog

struct CacheEntry {
    let terminal: TerminalContext
    var expiresAt: Date
}

final class TerminalIDCache {
    private static let cacheTTL: TimeInterval = 12 * 60 * 60
    private var entries: [String: CacheEntry] = [:]
    private let logger: Logger

    init(logger: Logger) {
        self.logger = logger
    }

    func clear(tty: String?) {
        if let tty {
            let normalized = normalizeTTY(tty)
            entries.removeValue(forKey: normalized)
            logger.ghosttykit("cleared cache tty=\(normalized)")
        } else {
            entries.removeAll()
            logger.ghosttykit("cleared all cache entries")
        }
    }

    func store(terminal: TerminalContext, for rawTTY: String) {
        let tty = normalizeTTY(rawTTY)
        entries[tty] = CacheEntry(terminal: terminal, expiresAt: Date().addingTimeInterval(Self.cacheTTL))
        logger.ghosttykit(
            "cached tty=\(tty) terminal_id=\(terminal.terminalID) " +
                "window_id=\(terminal.windowID ?? "") tab_id=\(terminal.tabID ?? "")"
        )
    }

    func terminal(for rawTTY: String) -> TerminalContext? {
        pruneExpired()
        let tty = normalizeTTY(rawTTY)
        return entries[tty]?.terminal
    }

    private func pruneExpired() {
        let now = Date()
        entries = entries.filter { $0.value.expiresAt > now }
    }
}
