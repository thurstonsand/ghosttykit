import Foundation
import OSLog
@testable import ghosttykitd

final class StubBridgeSessionManager: BridgeSessionManaging {
    func createBridge(terminal _: TerminalContext) throws -> BridgeCreateReply {
        BridgeCreateReply.ok(socketPath: "/tmp/bridge.sock", leaseToken: "token")
    }
}

final class SpyGhosttyController: GhosttyControlling {
    private let focused: TerminalContext
    private let splitResult: TerminalContext
    private(set) var controlledTerminal: TerminalContext?
    private(set) var splitCommand: String?
    private(set) var inputText: String?
    private(set) var inputSubmit: Bool?

    init(
        focusedTerminal: TerminalContext = mainTerminal(),
        splitResult: TerminalContext = splitTerminal()
    ) {
        focused = focusedTerminal
        self.splitResult = splitResult
    }

    func preflightAutomationPermission() throws -> Bool { true }

    func focusedTerminalContext() throws -> TerminalContext {
        focused
    }

    func readPasteboardContent() throws -> FrameStreamReply {
        FrameStreamReply(header: PasteStreamFrameHeader.text(byteCount: 0), streams: [.data(Data())])
    }

    func activateKeyTable(_: String, terminal: TerminalContext) throws {
        controlledTerminal = terminal
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
    }

    func toggleSplitZoom(terminal: TerminalContext) throws {
        controlledTerminal = terminal
    }

    func tabTerminalCount(terminal _: TerminalContext?) throws -> Int {
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
