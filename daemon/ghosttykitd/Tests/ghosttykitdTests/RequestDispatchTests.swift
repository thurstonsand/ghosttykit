import Foundation
import OSLog
@testable import ghosttykitd
import XCTest

final class RequestDispatchTests: XCTestCase {
    func testDecodeRejectsUnsupportedProtocolVersion() throws {
        assertDecodeError(#"{"version":2,"command":"doctor"}"#, code: ProtocolCode.protocolVersionMismatch)
    }

    func testDecodeRejectsUnknownCommand() throws {
        assertDecodeError(#"{"version":1,"command":"bad"}"#, code: ProtocolCode.unknownCommand)
    }

    func testCreateBridgeRequestRequiresMainContext() {
        let request = CreateBridgeRequest(version: 1, command: "bridge-create", rawTTY: "/dev/ttys001")
        let result = request.dispatch(using: bridgeContext())
        XCTAssertEqual(result.frameReply?.code, ProtocolCode.invalidRequest)
    }

    func testBridgeLeaseRequestRequiresBridgeContext() {
        let request = BridgeLeaseRequest(version: 1, command: "bridge-lease", token: "token")
        let result = request.dispatch(using: mainContext())
        XCTAssertEqual(result.frameReply?.code, ProtocolCode.invalidRequest)
    }

    func testBridgeContextIgnoresRequestTTYForTerminalCommands() throws {
        let ghostty = SpyGhosttyController()
        let terminal = bridgeTerminal()
        let context = bridgeContext(ghostty: ghostty, terminal: terminal)
        let request: FocusRequest = try decodeJSON(#"{"version":1,"command":"focus","tty":"/dev/remote-spoof","direction":"left","ack":true}"#)

        let result = request.dispatch(using: context)

        XCTAssertEqual(result.frameReply?.code, ProtocolCode.ok)
        XCTAssertEqual(ghostty.controlledTerminal?.terminalID, terminal.terminalID)
    }

    func testMainContextUsesFocusedTerminalWhenAllowed() throws {
        let ghostty = SpyGhosttyController(focusedTerminal: mainTerminal())
        let context = mainContext(ghostty: ghostty)

        let terminal = try context.terminal(for: "/dev/ttys001", focused: true)

        XCTAssertEqual(terminal.terminalID, mainTerminal().terminalID)
        XCTAssertEqual(context.cache.terminal(for: "/dev/ttys001")?.terminalID, mainTerminal().terminalID)
    }

    private func mainContext(ghostty: GhosttyControlling = SpyGhosttyController()) -> MainCommandContext {
        MainCommandContext(
            cache: TerminalIDCache(logger: testLogger()),
            ghostty: ghostty,
            logger: testLogger(),
            bridgeManager: StubBridgeSessionManager()
        )
    }

    private func bridgeContext(
        ghostty: GhosttyControlling = SpyGhosttyController(),
        terminal: TerminalContext = bridgeTerminal()
    ) -> BridgeCommandContext {
        BridgeCommandContext(
            cache: TerminalIDCache(logger: testLogger()),
            ghostty: ghostty,
            logger: testLogger(),
            terminal: terminal,
            lease: BridgeLease(token: "token", onRelease: {})
        )
    }

    private func testLogger() -> Logger {
        Logger(subsystem: "dev.ghosttykit.tests", category: "requests")
    }

    private func assertDecodeError(_ json: String, code: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try decodeCommand(from: Data(json.utf8)), file: file, line: line) { error in
            XCTAssertEqual(responseForError(error).code, code, file: file, line: line)
        }
    }

    private func decodeJSON<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }
}
