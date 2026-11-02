import Foundation
import OSLog
@testable import ghosttykitd

final class StubBridgeSessionManager: BridgeSessionManaging {
    func createBridge(tty _: String) throws -> BridgeCreateReply {
        BridgeCreateReply.ok(socketPath: "/tmp/bridge.sock", leaseToken: "token")
    }
}

final class SpyGhosttyController: GhosttyControlling {
    private let splitTTY: String
    private let splitResult: TerminalContext
    private let resolvedTerminal: TerminalContext?
    private(set) var resolvedTTYs: [String] = []
    private(set) var controlledTerminal: TerminalContext?
    private(set) var splitCommand: String?
    private(set) var splitCallCount = 0
    private(set) var inputText: String?
    private(set) var inputSubmit: Bool?
    private(set) var inputCallCount = 0
    private(set) var verifiedBindings: [String] = []
    var cachedBindingsAreLive = true
    var nextActionError: Error?
    var ghosttyVersion: String? = "1.4.0"

    init(
        splitTTY: String = "/dev/ttys020",
        splitResult: TerminalContext = splitTerminal(),
        resolvedTerminal: TerminalContext? = mainTerminal()
    ) {
        self.splitTTY = splitTTY
        self.splitResult = splitResult
        self.resolvedTerminal = resolvedTerminal
    }

    func preflightAutomationPermission() throws -> String? { ghosttyVersion }

    func accessibilityGranted() -> Bool { true }

    func terminalContext(forTTY tty: String) throws -> TerminalContext {
        resolvedTTYs.append(tty)
        guard let resolvedTerminal else { throw GhosttyKitError.terminalNotFound(tty) }
        return resolvedTerminal
    }

    func isBound(_ terminal: TerminalContext, to tty: String) throws -> Bool {
        verifiedBindings.append("\(terminal.terminalID)@\(tty)")
        return cachedBindingsAreLive
    }

    func readPasteboardContent() throws -> FrameStreamReply {
        FrameStreamReply(header: PasteStreamFrameHeader.text(byteCount: 0), streams: [.data(Data())])
    }

    func activateKeyTable(_: String, terminal: TerminalContext) throws {
        try consumeActionError()
        controlledTerminal = terminal
    }

    private func consumeActionError() throws {
        if let error = nextActionError {
            nextActionError = nil
            throw error
        }
    }

    func deactivateKeyTable(terminal: TerminalContext) throws {
        controlledTerminal = terminal
    }

    func focusSplit(direction _: Direction, terminal: TerminalContext) throws {
        controlledTerminal = terminal
    }

    func input(_ text: String, submit: Bool, terminal: TerminalContext) throws {
        controlledTerminal = terminal
        inputText = text
        inputSubmit = submit
        inputCallCount += 1
        try consumeActionError()
    }

    func toggleSplitZoom(terminal: TerminalContext) throws {
        controlledTerminal = terminal
    }

    func tabTerminalCount(terminal _: TerminalContext) throws -> Int {
        1
    }

    func split(
        direction _: Direction,
        cwd _: String?,
        command: String?,
        focus _: FocusTarget,
        terminal: TerminalContext
    ) throws -> (tty: String, terminal: TerminalContext) {
        controlledTerminal = terminal
        splitCommand = command
        splitCallCount += 1
        try consumeActionError()
        return (tty: splitTTY, terminal: splitResult)
    }

    func resize(direction _: Direction, amount _: ResizeAmount, terminal: TerminalContext) throws {
        controlledTerminal = terminal
    }
}

func mainTerminal() -> TerminalContext {
    TerminalContext(terminalID: "main-terminal", windowID: "main-window", tabID: "main-tab")
}

func bridgeTerminal() -> TerminalContext {
    TerminalContext(terminalID: "bridge-terminal", windowID: "bridge-window", tabID: "bridge-tab")
}

func splitTerminal() -> TerminalContext {
    TerminalContext(terminalID: "split-terminal", windowID: "main-window", tabID: "main-tab")
}
