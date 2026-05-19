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
    private(set) var controlledTerminal: TerminalContext?

    init(focusedTerminal: TerminalContext = mainTerminal()) {
        focused = focusedTerminal
    }

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

    func toggleSplitZoom(terminal: TerminalContext) throws {
        controlledTerminal = terminal
    }

    func tabTerminalCount(terminal _: TerminalContext?) throws -> Int {
        1
    }

    func split(
        direction _: Direction,
        cwd _: String?,
        command _: String?,
        focus _: FocusTarget,
        terminal: TerminalContext
    ) throws {
        controlledTerminal = terminal
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
