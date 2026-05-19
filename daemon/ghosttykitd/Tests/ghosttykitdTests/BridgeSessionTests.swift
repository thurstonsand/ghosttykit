import Foundation
import NIOCore
import NIOPosix
import OSLog
@testable import ghosttykitd
import XCTest

final class BridgeSessionTests: XCTestCase {
    func testLeaseAcceptsTokenAndCleansUpOnClose() throws {
        let root = temporaryBridgeRoot()
        let manager = BridgeSessionManager(logger: testLogger(), rootDirectory: root) { _, lease, request in
            request.dispatch(using: self.bridgeContext(lease: lease))
        }
        let reply = try manager.createBridge(terminal: testTerminal())
        let socketPath = try reply.socketPath.requireValue()
        let leaseToken = try reply.leaseToken.requireValue()

        let conn = try UnixJSONConnection(path: socketPath)
        try conn.send(["version": 1, "command": "bridge-lease", "token": leaseToken])
        let ack: FrameReply = try conn.readReply()
        XCTAssertNil(ack.errorForTest())
        try conn.close()

        XCTAssertTrue(waitUntil { !FileManager.default.fileExists(atPath: socketPath) })
    }

    func testLeaseRejectsInvalidTokenAndKeepsSocket() throws {
        let root = temporaryBridgeRoot()
        let manager = BridgeSessionManager(logger: testLogger(), rootDirectory: root) { _, lease, request in
            request.dispatch(using: self.bridgeContext(lease: lease))
        }
        let reply = try manager.createBridge(terminal: testTerminal())
        let socketPath = try reply.socketPath.requireValue()
        let leaseToken = try reply.leaseToken.requireValue()

        let conn = try UnixJSONConnection(path: socketPath)
        try conn.send(["version": 1, "command": "bridge-lease", "token": "wrong"])
        let ack: FrameReply = try conn.readReply()
        XCTAssertEqual(ack.code, ProtocolCode.invalidRequest)
        try conn.close()

        XCTAssertTrue(FileManager.default.fileExists(atPath: socketPath))

        let valid = try UnixJSONConnection(path: socketPath)
        try valid.send(["version": 1, "command": "bridge-lease", "token": leaseToken])
        let validAck: FrameReply = try valid.readReply()
        XCTAssertEqual(validAck.code, ProtocolCode.ok)
        try valid.close()
        _ = waitUntil { !FileManager.default.fileExists(atPath: socketPath) }
    }

    func testRequestRequiresActiveLease() throws {
        let root = temporaryBridgeRoot()
        let manager = BridgeSessionManager(logger: testLogger(), rootDirectory: root) { _, _, _ in
            .reply(.frame(FrameReply.ok("pong")))
        }
        let reply = try manager.createBridge(terminal: testTerminal())
        let socketPath = try reply.socketPath.requireValue()

        let conn = try UnixJSONConnection(path: socketPath)
        try conn.send(["version": 1, "command": "ping"])
        let ack: FrameReply = try conn.readReply()
        XCTAssertEqual(ack.code, ProtocolCode.invalidRequest)
        try conn.close()
    }

    func testRequestUsesBridgeBoundTerminal() throws {
        let root = temporaryBridgeRoot()
        let manager = BridgeSessionManager(logger: testLogger(), rootDirectory: root) { terminal, lease, request in
            if request is BridgeLeaseRequest {
                return request.dispatch(using: self.bridgeContext(lease: lease))
            }
            return .reply(.frame(FrameReply.ok(terminal.terminalID)))
        }
        let reply = try manager.createBridge(terminal: testTerminal())
        let socketPath = try reply.socketPath.requireValue()
        let leaseToken = try reply.leaseToken.requireValue()

        let lease = try UnixJSONConnection(path: socketPath)
        try lease.send(["version": 1, "command": "bridge-lease", "token": leaseToken])
        let leaseAck: FrameReply = try lease.readReply()
        XCTAssertEqual(leaseAck.code, ProtocolCode.ok)

        let request = try UnixJSONConnection(path: socketPath)
        try request.send(["version": 1, "command": "ping"])
        let replyFrame: FrameReply = try request.readReply()
        XCTAssertEqual(replyFrame.value, "terminal")
        try request.close()
        try lease.close()
    }

    private func temporaryBridgeRoot() -> URL {
        URL(fileURLWithPath: "/tmp")
            .appendingPathComponent("gkb-\(UUID().uuidString.prefix(8))")
    }

    private func testTerminal() -> TerminalContext {
        TerminalContext(terminalID: "terminal", windowID: "window", tabID: "tab")
    }

    private func bridgeContext(lease: BridgeLease) -> BridgeCommandContext {
        BridgeCommandContext(
            cache: TerminalIDCache(logger: testLogger()),
            ghostty: DryRunGhosttyController(),
            logger: testLogger(),
            terminal: testTerminal(),
            lease: lease
        )
    }

    private func testLogger() -> Logger {
        Logger(subsystem: "dev.ghosttykit.tests", category: "bridge")
    }

    private func waitUntil(_ predicate: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if predicate() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        return predicate()
    }
}
