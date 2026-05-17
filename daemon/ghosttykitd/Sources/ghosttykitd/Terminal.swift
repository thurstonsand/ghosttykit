import Foundation
import OSLog

func normalizeTTY(_ tty: String) -> String {
    tty.hasPrefix("/dev/") ? tty : "/dev/\(tty)"
}

struct TerminalContext {
    let terminalID: String
    let windowID: String?
    let tabID: String?
}

extension Logger {
    func ghosttykit(_ message: String) {
        info("\(message, privacy: .public)")
    }
}

enum Direction: String, Decodable {
    case left
    case down
    case up
    case right
}

enum FocusTarget: String, Decodable {
    case new
    case original
}
