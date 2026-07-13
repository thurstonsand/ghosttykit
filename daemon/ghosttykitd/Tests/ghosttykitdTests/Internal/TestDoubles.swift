import Foundation
import OSLog
@testable import ghosttykitd

final class StubBridgeSessionManager: BridgeSessionManaging {
    func createBridge(terminal _: TerminalContext) throws -> BridgeCreateReply {
        BridgeCreateReply.ok(socketPath: "/tmp/bridge.sock", leaseToken: "token")
    }
}

final class SpyGhosttyController: GhosttyControlling {
    private let splitResult: TerminalContext
    private let resolvedTerminal: TerminalContext?
    private(set) var resolvedTTYs: [String] = []
    private(set) var controlledTerminal: TerminalContext?
    private(set) var splitCommand: String?
    private(set) var splitCallCount = 0
    private(set) var inputText: String?
    private(set) var inputSubmit: Bool?
    private(set) var inputCallCount = 0
    var nextActionError: Error?

    init(
        splitResult: TerminalContext = splitTerminal(),
        resolvedTerminal: TerminalContext? = mainTerminal()
    ) {
        self.splitResult = splitResult
        self.resolvedTerminal = resolvedTerminal
    }

    func preflightAutomationPermission() throws -> Bool { true }

    func terminalContext(forTTY tty: String) throws -> TerminalContext {
        resolvedTTYs.append(tty)
        guard let resolvedTerminal else { throw GhosttyKitError.terminalNotFound(tty) }
        return resolvedTerminal
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
    ) throws -> TerminalContext {
        controlledTerminal = terminal
        splitCommand = command
        splitCallCount += 1
        try consumeActionError()
        return splitResult
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

func escrow(_ rendezvous: SpawnRendezvous, terminal: TerminalContext) -> String {
    let token = UUID().uuidString.lowercased()
    rendezvous.escrow(token: token, terminal: terminal)
    return token
}

func testSpawnWrapper() -> SpawnWrapper {
    SpawnWrapper(
        gtyPath: "/opt/ghosttykit/bin/gty",
        socketPath: "/opt/run/gk.sock",
        loginShell: { "/bin/zsh" }
    )
}
