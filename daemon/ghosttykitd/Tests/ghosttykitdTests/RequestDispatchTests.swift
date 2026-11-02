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
        let request = CreateBridgeRequest(
            version: 1, command: "bridge-create", explicitTTY: nil, callerTTY: "/dev/ttys001"
        )
        let result = request.dispatch(using: bridgeContext())
        XCTAssertEqual(result.frameReply?.code, ProtocolCode.invalidRequest)
    }

    func testBridgeLeaseRequestRequiresBridgeContext() {
        let request = BridgeLeaseRequest(version: 1, command: "bridge-lease", token: "token")
        let result = request.dispatch(using: mainContext())
        XCTAssertEqual(result.frameReply?.code, ProtocolCode.invalidRequest)
    }

    func testBridgeActsOnItsOwnTTYWhateverTheCallerTTY() throws {
        let ghostty = SpyGhosttyController(resolvedTerminal: bridgeTerminal())
        let request: FocusRequest = try decodeJSON(
            #"{"version":1,"command":"focus","callerTty":"/dev/pts/3","direction":"left","ack":true}"#
        )

        let result = request.dispatch(using: bridgeContext(ghostty: ghostty, tty: "/dev/ttys005"))

        XCTAssertEqual(result.frameReply?.code, ProtocolCode.ok)
        XCTAssertEqual(ghostty.controlledTerminal?.terminalID, bridgeTerminal().terminalID)
        XCTAssertEqual(ghostty.resolvedTTYs, ["/dev/ttys005"])
    }

    func testBridgeActsOnItsOwnTTYWhenCallerHasNoTTY() throws {
        let ghostty = SpyGhosttyController(resolvedTerminal: bridgeTerminal())
        let request: TerminalIDRequest = try decodeJSON(#"{"version":1,"command":"terminal-id"}"#)

        let result = request.dispatch(using: bridgeContext(ghostty: ghostty))

        XCTAssertEqual(result.frameReply?.code, ProtocolCode.ok)
        XCTAssertEqual(result.frameReply?.value, bridgeTerminal().terminalID)
    }

    func testBridgeRejectsExplicitTTY() throws {
        let ghostty = SpyGhosttyController()
        let context = bridgeContext(ghostty: ghostty)
        let input: InputRequest = try decodeJSON(
            #"{"version":1,"command":"input","tty":"/dev/ttys009","callerTty":"/dev/pts/3","text":"whoami","ack":true}"#
        )
        let clearCache: ClearCacheRequest = try decodeJSON(
            #"{"version":1,"command":"clear-cache","tty":"/dev/ttys009","ack":true}"#
        )

        XCTAssertEqual(input.dispatch(using: context).frameReply?.code, ProtocolCode.invalidRequest)
        XCTAssertEqual(clearCache.dispatch(using: context).frameReply?.code, ProtocolCode.invalidRequest)
        XCTAssertNil(ghostty.inputText)
        XCTAssertNil(ghostty.controlledTerminal)
    }

    func testMainPrefersExplicitTTYOverCallerTTY() throws {
        let ghostty = SpyGhosttyController()
        let context = mainContext(ghostty: ghostty)
        context.cache.store(terminal: splitTerminal(), for: "/dev/ttys009")
        context.cache.store(terminal: mainTerminal(), for: "/dev/ttys001")
        let request: FocusRequest = try decodeJSON(
            #"{"version":1,"command":"focus","tty":"/dev/ttys009","callerTty":"/dev/ttys001","direction":"left","ack":true}"#
        )

        let result = request.dispatch(using: context)

        XCTAssertEqual(result.frameReply?.code, ProtocolCode.ok)
        XCTAssertEqual(ghostty.controlledTerminal?.terminalID, splitTerminal().terminalID)
    }

    func testMainRejectsRequestNamingNoTerminal() throws {
        let ghostty = SpyGhosttyController()
        let request: FocusRequest = try decodeJSON(
            #"{"version":1,"command":"focus","direction":"left","ack":true}"#
        )

        let result = request.dispatch(using: mainContext(ghostty: ghostty))

        XCTAssertEqual(result.frameReply?.code, ProtocolCode.invalidRequest)
        XCTAssertNil(ghostty.controlledTerminal)
    }

    func testClearCacheClearsEverythingOnlyWhenAskedTo() throws {
        let context = mainContext()
        context.cache.store(terminal: mainTerminal(), for: "/dev/ttys001")
        context.cache.store(terminal: splitTerminal(), for: "/dev/ttys009")
        let untargeted: ClearCacheRequest = try decodeJSON(#"{"version":1,"command":"clear-cache","ack":true}"#)
        let own: ClearCacheRequest = try decodeJSON(
            #"{"version":1,"command":"clear-cache","callerTty":"/dev/ttys001","ack":true}"#
        )
        let all: ClearCacheRequest = try decodeJSON(#"{"version":1,"command":"clear-cache","all":true,"ack":true}"#)

        XCTAssertEqual(untargeted.dispatch(using: context).frameReply?.code, ProtocolCode.invalidRequest)
        XCTAssertNotNil(context.cache.terminal(for: "/dev/ttys001"))
        XCTAssertEqual(own.dispatch(using: context).frameReply?.code, ProtocolCode.ok)
        XCTAssertNil(context.cache.terminal(for: "/dev/ttys001"))
        XCTAssertNotNil(context.cache.terminal(for: "/dev/ttys009"))
        XCTAssertEqual(all.dispatch(using: context).frameReply?.code, ProtocolCode.ok)
        XCTAssertNil(context.cache.terminal(for: "/dev/ttys009"))
    }

    func testSplitRepliesNewTerminalTTYAndOverwritesItsStaleBinding() throws {
        let ghostty = SpyGhosttyController(splitTTY: "/dev/ttys020")
        let context = mainContext(ghostty: ghostty)
        context.cache.store(terminal: bridgeTerminal(), for: "/dev/ttys020")

        let result = try splitRequest().dispatch(using: context)

        XCTAssertEqual(result.frameReply?.code, ProtocolCode.ok)
        XCTAssertEqual(result.frameReply?.value, "/dev/ttys020")
        XCTAssertEqual(context.cache.terminal(for: "/dev/ttys020")?.terminalID, splitTerminal().terminalID)
        XCTAssertNil(ghostty.splitCommand)
    }

    func testSplitPassesCommandThrough() throws {
        let ghostty = SpyGhosttyController()
        let context = mainContext(ghostty: ghostty)

        let result = try splitRequest(commandText: "nvim .").dispatch(using: context)

        XCTAssertEqual(result.frameReply?.code, ProtocolCode.ok)
        XCTAssertEqual(ghostty.splitCommand, "nvim .")
    }

    func testDoctorRequiresGhostty14() throws {
        let cases: [(version: String, status: String)] = [
            ("1.3.1", "failed"),
            ("0.9.9", "failed"),
            ("1.4.0", "ok"),
            ("1.10.0", "ok"),
            ("1.4.1-dev+abc123", "ok"),
            ("2.0.0", "ok")
        ]
        for (version, status) in cases {
            let ghostty = SpyGhosttyController()
            ghostty.ghosttyVersion = version

            let result = DoctorRequest(version: 1, command: "doctor").dispatch(using: mainContext(ghostty: ghostty))

            guard case let .reply(.frame(frame)) = result, let reply = frame as? DoctorReply else {
                return XCTFail("doctor did not reply with a frame for \(version)")
            }
            XCTAssertEqual(reply.checks.first { $0.name == "ghostty" }?.status, status, version)
            XCTAssertEqual(reply.healthy, status == "ok", version)
        }
    }

    func testInputDeliversTextToBoundTerminal() throws {
        let ghostty = SpyGhosttyController()
        let context = mainContext(ghostty: ghostty)
        context.cache.store(terminal: splitTerminal(), for: "/dev/ttys009")
        let request: InputRequest = try decodeJSON(
            #"{"version":1,"command":"input","tty":"/dev/ttys009","text":"nvim .","submit":true,"ack":true}"#
        )

        let result = request.dispatch(using: context)

        XCTAssertEqual(result.frameReply?.code, ProtocolCode.ok)
        XCTAssertEqual(ghostty.controlledTerminal?.terminalID, splitTerminal().terminalID)
        XCTAssertEqual(ghostty.inputText, "nvim .")
        XCTAssertEqual(ghostty.inputSubmit, true)
    }

    func testInputFailsWhenTTYResolutionFindsNoTerminal() throws {
        let request: InputRequest = try decodeJSON(
            #"{"version":1,"command":"input","tty":"/dev/ttys009","text":"nvim .","ack":true}"#
        )

        let result = request.dispatch(using: mainContext(ghostty: SpyGhosttyController(resolvedTerminal: nil)))

        XCTAssertEqual(result.frameReply?.code, ProtocolCode.terminalNotFound)
    }

    func testMainContextResolvesUnknownTTYDeterministically() throws {
        let ghostty = SpyGhosttyController(resolvedTerminal: mainTerminal())
        let context = mainContext(ghostty: ghostty)

        let terminal = try context.terminal(explicitTTY: nil, callerTTY: "/dev/ttys001")

        XCTAssertEqual(terminal.terminalID, mainTerminal().terminalID)
        XCTAssertEqual(context.cache.terminal(for: "/dev/ttys001")?.terminalID, mainTerminal().terminalID)
        XCTAssertEqual(ghostty.resolvedTTYs, ["/dev/ttys001"])
    }

    func testTerminalIDRefreshRebindsTTY() throws {
        let ghostty = SpyGhosttyController(resolvedTerminal: splitTerminal())
        let context = mainContext(ghostty: ghostty)
        context.cache.store(terminal: mainTerminal(), for: "/dev/ttys009")
        let request: TerminalIDRequest = try decodeJSON(
            #"{"version":1,"command":"terminal-id","tty":"/dev/ttys009","refresh":true}"#
        )

        let result = request.dispatch(using: context)

        XCTAssertEqual(result.frameReply?.code, ProtocolCode.ok)
        XCTAssertEqual(result.frameReply?.value, splitTerminal().terminalID)
        XCTAssertEqual(context.cache.terminal(for: "/dev/ttys009")?.terminalID, splitTerminal().terminalID)
    }

    func testCachedBindingIsUsedOnlyWhileGhosttyConfirmsIt() throws {
        let ghostty = SpyGhosttyController(resolvedTerminal: splitTerminal())
        let context = mainContext(ghostty: ghostty)
        context.cache.store(terminal: bridgeTerminal(), for: "/dev/ttys009")
        let request: KeyTableActivateRequest = try decodeJSON(
            #"{"version":1,"command":"key-table-activate","tty":"/dev/ttys009","table":"nvim","ack":true}"#
        )

        XCTAssertEqual(request.dispatch(using: context).frameReply?.code, ProtocolCode.ok)
        XCTAssertEqual(ghostty.controlledTerminal?.terminalID, bridgeTerminal().terminalID)
        XCTAssertTrue(ghostty.resolvedTTYs.isEmpty)

        ghostty.cachedBindingsAreLive = false
        XCTAssertEqual(request.dispatch(using: context).frameReply?.code, ProtocolCode.ok)
        XCTAssertEqual(ghostty.controlledTerminal?.terminalID, splitTerminal().terminalID)
        XCTAssertEqual(context.cache.terminal(for: "/dev/ttys009")?.terminalID, splitTerminal().terminalID)
        XCTAssertEqual(ghostty.resolvedTTYs, ["/dev/ttys009"])
        XCTAssertEqual(ghostty.verifiedBindings, ["bridge-terminal@/dev/ttys009", "bridge-terminal@/dev/ttys009"])
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
        tty: String = "/dev/ttys005"
    ) -> BridgeCommandContext {
        BridgeCommandContext(
            cache: TerminalIDCache(logger: testLogger()),
            ghostty: ghostty,
            logger: testLogger(),
            tty: tty,
            lease: BridgeLease(token: "token", onRelease: {})
        )
    }

    private func splitRequest(commandText: String? = nil) throws -> SplitRequest {
        let command = commandText.map { #","commandText":"\#($0)""# } ?? ""
        return try decodeJSON(
            #"{"version":1,"command":"split","tty":"/dev/ttys001","direction":"left","ack":true"# +
                command + "}"
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
