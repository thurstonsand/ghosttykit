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

    func testSpawnClaimBindsMintedTerminal() throws {
        let rendezvous = SpawnRendezvous(logger: testLogger())
        let context = mainContext(spawnRendezvous: rendezvous)
        let token = escrow(rendezvous, terminal: mainTerminal())
        let request = spawnClaimRequest(token: token)

        let result = request.dispatch(using: context)

        XCTAssertEqual(result.frameReply?.code, ProtocolCode.ok)
        XCTAssertEqual(context.cache.terminal(for: "/dev/ttys009")?.terminalID, mainTerminal().terminalID)
    }

    func testSpawnClaimOverwritesExistingCacheEntry() throws {
        let rendezvous = SpawnRendezvous(logger: testLogger())
        let context = mainContext(spawnRendezvous: rendezvous)
        context.cache.store(terminal: bridgeTerminal(), for: "/dev/ttys009")
        let token = escrow(rendezvous, terminal: mainTerminal())

        let result = spawnClaimRequest(token: token).dispatch(using: context)

        XCTAssertEqual(result.frameReply?.code, ProtocolCode.ok)
        XCTAssertEqual(context.cache.terminal(for: "/dev/ttys009")?.terminalID, mainTerminal().terminalID)
    }

    func testSpawnClaimUnknownTokenFailsWithoutClearingCache() throws {
        let context = mainContext()
        context.cache.store(terminal: mainTerminal(), for: "/dev/ttys009")

        let result = spawnClaimRequest(token: "deadbeef").dispatch(using: context)

        XCTAssertEqual(result.frameReply?.code, ProtocolCode.spawnTokenNotFound)
        XCTAssertEqual(context.cache.terminal(for: "/dev/ttys009")?.terminalID, mainTerminal().terminalID)
    }

    func testSpawnClaimBurnsToken() throws {
        let rendezvous = SpawnRendezvous(logger: testLogger())
        let context = mainContext(spawnRendezvous: rendezvous)
        let token = escrow(rendezvous, terminal: mainTerminal())

        XCTAssertEqual(spawnClaimRequest(token: token).dispatch(using: context).frameReply?.code, ProtocolCode.ok)
        let replay = spawnClaimRequest(token: token).dispatch(using: context)

        XCTAssertEqual(replay.frameReply?.code, ProtocolCode.spawnTokenNotFound)
        XCTAssertEqual(context.cache.terminal(for: "/dev/ttys009")?.terminalID, mainTerminal().terminalID)
    }

    func testSpawnClaimRequiresMainContext() {
        let request = spawnClaimRequest(token: "token")
        let result = request.dispatch(using: bridgeContext())
        XCTAssertEqual(result.frameReply?.code, ProtocolCode.invalidRequest)
    }

    func testSplitWithWaitRepliesClaimedTTY() async throws {
        let ghostty = SpyGhosttyController()
        let rendezvous = SpawnRendezvous(logger: testLogger())
        let context = mainContext(ghostty: ghostty, spawnRendezvous: rendezvous, spawnWrapper: testSpawnWrapper())

        let result = try splitRequest().dispatch(using: context)
        let token = try extractSpawnToken(from: ghostty.splitCommand).requireValue()
        XCTAssertEqual(spawnClaimRequest(token: token).dispatch(using: context).frameReply?.code, ProtocolCode.ok)

        let reply = try await result.deferredReply.requireValue()()
        XCTAssertEqual(reply.frame?.code, ProtocolCode.ok)
        XCTAssertEqual(reply.frame?.value, "/dev/ttys009")
        XCTAssertEqual(context.cache.terminal(for: "/dev/ttys009")?.terminalID, splitTerminal().terminalID)
    }

    func testSplitWithWaitTimesOutWithEmptyValue() async throws {
        let rendezvous = SpawnRendezvous(logger: testLogger(), timeout: 0.05)
        let context = mainContext(spawnRendezvous: rendezvous, spawnWrapper: testSpawnWrapper())

        let result = try splitRequest().dispatch(using: context)

        let reply = try await result.deferredReply.requireValue()()
        XCTAssertEqual(reply.frame?.code, ProtocolCode.ok)
        XCTAssertNil(reply.frame?.value)
    }

    func testSplitWithoutWrapperRepliesImmediatelyAndPassesCommandThrough() throws {
        let ghostty = SpyGhosttyController()
        let context = mainContext(ghostty: ghostty)

        let result = try splitRequest(commandText: "nvim .").dispatch(using: context)

        XCTAssertEqual(result.frameReply?.code, ProtocolCode.ok)
        XCTAssertEqual(ghostty.splitCommand, "nvim .")
    }

    func testSplitWrapsGivenCommand() throws {
        let ghostty = SpyGhosttyController()
        let context = mainContext(ghostty: ghostty, spawnWrapper: testSpawnWrapper())

        _ = try splitRequest(commandText: "nvim .").dispatch(using: context)

        let command = try ghostty.splitCommand.requireValue()
        XCTAssertTrue(command.hasPrefix("/bin/sh -c "))
        XCTAssertTrue(command.contains("spawn-claim"))
        XCTAssertTrue(command.contains("exec\\ nvim\\ ."))
    }

    func testBareSplitWrapsLoginShell() throws {
        let ghostty = SpyGhosttyController()
        let context = mainContext(ghostty: ghostty, spawnWrapper: testSpawnWrapper())

        _ = try splitRequest().dispatch(using: context)

        let command = try ghostty.splitCommand.requireValue()
        XCTAssertTrue(command.contains("exec\\ -l\\ /bin/zsh"))
    }

    func testSplitDoesNotRetryAfterPartialFailure() throws {
        let ghostty = SpyGhosttyController(resolvedTerminal: splitTerminal())
        let context = mainContext(ghostty: ghostty)
        context.cache.store(terminal: bridgeTerminal(), for: "/dev/ttys009")
        ghostty.nextActionError = AppleEventControlError.objectNotFound(operation: "focus split")
        let request: SplitRequest = try decodeJSON(
            #"{"version":1,"command":"split","tty":"/dev/ttys009","direction":"right","ack":true}"#
        )

        let result = request.dispatch(using: context)

        XCTAssertNotEqual(result.frameReply?.code, ProtocolCode.ok)
        XCTAssertEqual(ghostty.splitCallCount, 1)
        XCTAssertTrue(ghostty.resolvedTTYs.isEmpty)
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

    func testInputDoesNotRetryAfterPartialFailure() throws {
        let ghostty = SpyGhosttyController(resolvedTerminal: splitTerminal())
        let context = mainContext(ghostty: ghostty)
        context.cache.store(terminal: bridgeTerminal(), for: "/dev/ttys009")
        ghostty.nextActionError = AppleEventControlError.objectNotFound(operation: "send key")
        let request: InputRequest = try decodeJSON(
            #"{"version":1,"command":"input","tty":"/dev/ttys009","text":"nvim .","submit":true,"ack":true}"#
        )

        let result = request.dispatch(using: context)

        XCTAssertNotEqual(result.frameReply?.code, ProtocolCode.ok)
        XCTAssertEqual(ghostty.inputCallCount, 1)
        XCTAssertTrue(ghostty.resolvedTTYs.isEmpty)
    }

    func testBridgeInputIgnoresRequestTTY() throws {
        let ghostty = SpyGhosttyController()
        let terminal = bridgeTerminal()
        let context = bridgeContext(ghostty: ghostty, terminal: terminal)
        let request: InputRequest = try decodeJSON(
            #"{"version":1,"command":"input","tty":"/dev/remote-spoof","text":"whoami","ack":true}"#
        )

        let result = request.dispatch(using: context)

        XCTAssertEqual(result.frameReply?.code, ProtocolCode.ok)
        XCTAssertEqual(ghostty.controlledTerminal?.terminalID, terminal.terminalID)
    }

    func testMainContextResolvesUnknownTTYDeterministically() throws {
        let ghostty = SpyGhosttyController(resolvedTerminal: mainTerminal())
        let context = mainContext(ghostty: ghostty)

        let terminal = try context.terminal(for: "/dev/ttys001")

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

    func testStaleBindingHealsWithinOneRequest() throws {
        let ghostty = SpyGhosttyController(resolvedTerminal: splitTerminal())
        let context = mainContext(ghostty: ghostty)
        context.cache.store(terminal: bridgeTerminal(), for: "/dev/ttys009")
        ghostty.nextActionError = AppleEventControlError.objectNotFound(operation: "perform Ghostty action")
        let request: KeyTableActivateRequest = try decodeJSON(
            #"{"version":1,"command":"key-table-activate","tty":"/dev/ttys009","table":"nvim","ack":true}"#
        )

        let result = request.dispatch(using: context)

        XCTAssertEqual(result.frameReply?.code, ProtocolCode.ok)
        XCTAssertEqual(ghostty.controlledTerminal?.terminalID, splitTerminal().terminalID)
        XCTAssertEqual(context.cache.terminal(for: "/dev/ttys009")?.terminalID, splitTerminal().terminalID)
        XCTAssertEqual(ghostty.resolvedTTYs, ["/dev/ttys009"])
    }

    private func mainContext(
        ghostty: GhosttyControlling = SpyGhosttyController(),
        spawnRendezvous: SpawnRendezvous? = nil,
        spawnWrapper: SpawnWrapper? = nil
    ) -> MainCommandContext {
        MainCommandContext(
            cache: TerminalIDCache(logger: testLogger()),
            ghostty: ghostty,
            logger: testLogger(),
            bridgeManager: StubBridgeSessionManager(),
            spawnRendezvous: spawnRendezvous ?? SpawnRendezvous(logger: testLogger()),
            spawnWrapper: spawnWrapper
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
            lease: BridgeLease(token: "token", onRelease: {}),
            spawnRendezvous: SpawnRendezvous(logger: testLogger()),
            spawnWrapper: nil
        )
    }

    private func spawnClaimRequest(token: String) -> SpawnClaimRequest {
        SpawnClaimRequest(version: 1, command: "spawn-claim", rawTTY: "/dev/ttys009", spawnToken: token)
    }

    private func splitRequest(commandText: String? = nil) throws -> SplitRequest {
        let command = commandText.map { #","commandText":"\#($0)""# } ?? ""
        return try decodeJSON(
            #"{"version":1,"command":"split","tty":"/dev/ttys001","direction":"left","ack":true"# +
                command + "}"
        )
    }

    private func extractSpawnToken(from command: String?) -> String? {
        guard let command, let range = command.range(of: "spawn-claim\\ ") else { return nil }
        return String(command[range.upperBound...].prefix { $0 != "\\" })
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
