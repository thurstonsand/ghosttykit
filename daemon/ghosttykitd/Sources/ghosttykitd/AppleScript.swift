import AppKit
import Foundation

enum GhosttyKitError: Error, LocalizedError {
    case invalidResize(String)
    case terminalNotFound(String)

    var errorDescription: String? {
        switch self {
        case let .invalidResize(value): "invalid resize amount: \(value)"
        case let .terminalNotFound(value): "no Ghostty terminal is associated with \(value)"
        }
    }

    var protocolCode: String {
        switch self {
        case .invalidResize:
            ProtocolCode.invalidRequest
        case .terminalNotFound:
            ProtocolCode.terminalNotFound
        }
    }
}

protocol GhosttyControlling {
    func focusedTerminalContext() throws -> TerminalContext
    func readPasteboardContent() throws -> FrameStreamReply
    func activateKeyTable(_ table: String, terminal: TerminalContext) throws
    func deactivateKeyTable(terminal: TerminalContext) throws
    func focusSplit(direction: Direction, terminal: TerminalContext) throws
    func toggleSplitZoom(terminal: TerminalContext) throws
    func tabTerminalCount(terminal: TerminalContext?) throws -> Int
    func split(
        direction: Direction,
        cwd: String?,
        command: String?,
        focus: FocusTarget,
        terminal: TerminalContext
    ) throws
    func resize(direction: Direction, amount: ResizeAmount, terminal: TerminalContext) throws
}

final class DryRunGhosttyController: GhosttyControlling {
    private let terminal = TerminalContext(
        terminalID: "dry-run-terminal",
        windowID: "dry-run-window",
        tabID: "dry-run-tab"
    )
    private let pasteText: String?

    init(pasteText: String? = nil) {
        self.pasteText = pasteText
    }

    func focusedTerminalContext() throws -> TerminalContext {
        terminal
    }

    func readPasteboardContent() throws -> FrameStreamReply {
        guard let pasteText else { return try readSystemPasteboardContent() }
        let data = Data(pasteText.utf8)
        return FrameStreamReply(header: PasteStreamFrameHeader.text(byteCount: data.count), streams: [.data(data)])
    }

    func activateKeyTable(_: String, terminal _: TerminalContext) throws {}

    func deactivateKeyTable(terminal _: TerminalContext) throws {}

    func focusSplit(direction _: Direction, terminal _: TerminalContext) throws {}

    func toggleSplitZoom(terminal _: TerminalContext) throws {}

    func tabTerminalCount(terminal _: TerminalContext?) throws -> Int {
        1
    }

    func split(
        direction _: Direction,
        cwd _: String?,
        command _: String?,
        focus _: FocusTarget,
        terminal _: TerminalContext
    ) throws {}

    func resize(direction _: Direction, amount _: ResizeAmount, terminal _: TerminalContext) throws {}
}

final class AppleScriptGhosttyController: GhosttyControlling {
    func focusedTerminalContext() throws -> TerminalContext {
        let source = """
        tell application "Ghostty"
            set targetWindow to front window
            set targetTab to selected tab of targetWindow
            set targetTerminal to focused terminal of targetTab
            return (id of targetTerminal) & linefeed & (id of targetWindow) & linefeed & (id of targetTab)
        end tell
        """
        let parts = try stringValue(from: executeAppleScript(source)).split(
            separator: "\n",
            omittingEmptySubsequences: false
        )
        guard let terminalID = parts.first.map(String.init), !terminalID.isEmpty else {
            throw NSError(
                domain: "ghosttykitd",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "failed to resolve focused terminal id"]
            )
        }
        return TerminalContext(
            terminalID: terminalID,
            windowID: parts.count > 1 ? String(parts[1]) : nil,
            tabID: parts.count > 2 ? String(parts[2]) : nil
        )
    }

    func readPasteboardContent() throws -> FrameStreamReply {
        try readSystemPasteboardContent()
    }

    func activateKeyTable(_ table: String, terminal: TerminalContext) throws {
        try runGhosttyAction("activate_key_table:\(table)", terminal: terminal)
    }

    func deactivateKeyTable(terminal: TerminalContext) throws {
        try runGhosttyAction("deactivate_key_table", terminal: terminal)
    }

    func focusSplit(direction: Direction, terminal: TerminalContext) throws {
        try runGhosttyAction("goto_split:\(direction.rawValue)", terminal: terminal)
    }

    func toggleSplitZoom(terminal: TerminalContext) throws {
        try runGhosttyAction("toggle_split_zoom", terminal: terminal)
    }

    func tabTerminalCount(terminal: TerminalContext? = nil) throws -> Int {
        let source = if let tabID = terminal?.tabID {
            """
            tell application "Ghostty"
                return count of terminals of tab id "\(escapeAppleScriptString(tabID))" of front window
            end tell
            """
        } else {
            """
            tell application "Ghostty"
                return count of terminals of selected tab of front window
            end tell
            """
        }
        return try intValue(from: executeAppleScript(source))
    }

    func split(
        direction: Direction,
        cwd: String?,
        command: String?,
        focus: FocusTarget,
        terminal: TerminalContext
    ) throws {
        let escapedCwd = cwd.map(escapeAppleScriptString)
        let escapedCommand = command.map(escapeAppleScriptString)
        let focusTarget = focus == .original ? "targetTerminal" : "newTerminal"

        let source = """
        tell application "Ghostty"
            set targetTerminal to \(terminalSpecifier(id: terminal.terminalID))
            set cfg to new surface configuration
        \(escapedCwd.map { "    set initial working directory of cfg to \"\($0)\"" } ?? "")
        \(escapedCommand.map { "    set command of cfg to \"\($0)\"" } ?? "")
            set newTerminal to split targetTerminal direction \(direction.rawValue) with configuration cfg
            focus \(focusTarget)
        end tell
        """

        _ = try executeAppleScript(source)
    }

    func resize(direction: Direction, amount: ResizeAmount, terminal: TerminalContext) throws {
        let pixels: Int
        switch (amount.pixels, amount.percent) {
        case (.some(let value), nil):
            pixels = value
        case (nil, let .some(value)):
            guard value > 0 else { throw GhosttyKitError.invalidResize("percent must be greater than 0") }
            let dimension = try windowDimension(for: direction, terminal: terminal)
            pixels = max(Int(Double(dimension) * value / 100.0), 1)
        default:
            throw GhosttyKitError.invalidResize("specify exactly one of pixels or percent")
        }

        guard pixels > 0 else { throw GhosttyKitError.invalidResize("pixels must be greater than 0") }
        try runGhosttyAction("resize_split:\(direction.rawValue),\(pixels)", terminal: terminal)
    }

    private func windowDimension(for direction: Direction, terminal: TerminalContext) throws -> Int {
        let axisIndex = (direction == .left || direction == .right) ? 1 : 2
        let windowIndex = try ghosttyWindowIndex(windowID: terminal.windowID)
        let source = """
        tell application "System Events"
            tell process "Ghostty"
                if (count of windows) is 0 then error "Ghostty has no windows"
                set winSize to size of window \(windowIndex)
                return item \(axisIndex) of winSize
            end tell
        end tell
        """
        return try intValue(from: executeAppleScript(source))
    }

    private func ghosttyWindowIndex(windowID: String?) throws -> Int {
        guard let windowID else { return 1 }
        let source = """
        tell application "Ghostty"
            repeat with i from 1 to count of windows
                if id of window i is "\(escapeAppleScriptString(windowID))" then return i
            end repeat
        end tell
        return 1
        """
        return try intValue(from: executeAppleScript(source))
    }

    private func runGhosttyAction(_ action: String, terminal: TerminalContext) throws {
        let source = """
        tell application "Ghostty"
            set t to \(terminalSpecifier(id: terminal.terminalID))
            perform action "\(escapeAppleScriptString(action))" on t
        end tell
        """
        _ = try executeAppleScript(source)
    }

    private func executeAppleScript(_ source: String) throws -> NSAppleEventDescriptor {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            throw NSError(
                domain: "ghosttykitd",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "failed to compile AppleScript"]
            )
        }

        let result = script.executeAndReturnError(&error)
        if let error {
            let message = error[NSAppleScript.errorMessage] as? String ?? "AppleScript failed"
            var userInfo = error as? [String: Any] ?? [:]
            userInfo[NSLocalizedDescriptionKey] = message
            throw NSError(domain: "ghosttykitd", code: 1, userInfo: userInfo)
        }
        return result
    }

    private func stringValue(from descriptor: NSAppleEventDescriptor) throws -> String {
        descriptor.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func intValue(from descriptor: NSAppleEventDescriptor) throws -> Int {
        if let stringValue = descriptor.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
           let intValue = Int(stringValue) {
            return intValue
        }

        let int32Value = Int(descriptor.int32Value)
        if int32Value != 0 || descriptor.stringValue == nil {
            return int32Value
        }

        throw NSError(
            domain: "ghosttykitd",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "failed to decode AppleScript integer result"]
        )
    }

    private func escapeAppleScriptString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func terminalSpecifier(id terminalID: String) -> String {
        "terminal id \"\(escapeAppleScriptString(terminalID))\""
    }
}
