import Foundation
import OSLog
@testable import ghosttykitd
import XCTest

final class SpawnRendezvousTests: XCTestCase {
    func testClaimReturnsMintedTerminalAndResumesWaiter() {
        let rendezvous = makeRendezvous()
        let token = escrow(rendezvous, terminal: mainTerminal())
        let waited = expectation(description: "waiter resumed")
        var claimedTTY: String?
        rendezvous.park(token: token) { tty in
            claimedTTY = tty
            waited.fulfill()
        }

        let terminal = rendezvous.claim(token: token, tty: "/dev/ttys004")

        wait(for: [waited], timeout: 1)
        XCTAssertEqual(terminal?.terminalID, mainTerminal().terminalID)
        XCTAssertEqual(claimedTTY, "/dev/ttys004")
    }

    func testClaimConsumesToken() {
        let rendezvous = makeRendezvous()
        let token = escrow(rendezvous, terminal: mainTerminal())

        XCTAssertNotNil(rendezvous.claim(token: token, tty: "/dev/ttys004"))
        XCTAssertNil(rendezvous.claim(token: token, tty: "/dev/ttys004"))
    }

    func testUnknownTokenClaimReturnsNil() {
        XCTAssertNil(makeRendezvous().claim(token: "deadbeef", tty: "/dev/ttys004"))
    }

    func testParkOnUnknownTokenResumesImmediatelyWithNil() {
        let rendezvous = makeRendezvous()
        let waited = expectation(description: "waiter resumed")
        var claimedTTY: String? = "sentinel"
        rendezvous.park(token: "deadbeef") { tty in
            claimedTTY = tty
            waited.fulfill()
        }

        wait(for: [waited], timeout: 1)
        XCTAssertNil(claimedTTY)
    }

    func testSweepRemovesUnclaimedTokenAndResumesWaiterWithNil() {
        let rendezvous = makeRendezvous(timeout: 0.05)
        let token = escrow(rendezvous, terminal: mainTerminal())
        let waited = expectation(description: "waiter resumed")
        var claimedTTY: String? = "sentinel"
        rendezvous.park(token: token) { tty in
            claimedTTY = tty
            waited.fulfill()
        }

        wait(for: [waited], timeout: 1)
        XCTAssertNil(claimedTTY)
        XCTAssertNil(rendezvous.claim(token: token, tty: "/dev/ttys004"))
    }

    func testDistinctMintsClaimIndependently() {
        let rendezvous = makeRendezvous()
        let first = escrow(rendezvous, terminal: mainTerminal())
        let second = escrow(rendezvous, terminal: bridgeTerminal())

        XCTAssertEqual(rendezvous.claim(token: second, tty: "/dev/ttys005")?.terminalID, bridgeTerminal().terminalID)
        XCTAssertEqual(rendezvous.claim(token: first, tty: "/dev/ttys004")?.terminalID, mainTerminal().terminalID)
    }

    private func makeRendezvous(timeout: TimeInterval = SpawnRendezvous.spawnTimeout) -> SpawnRendezvous {
        SpawnRendezvous(logger: Logger(subsystem: "dev.ghosttykit.tests", category: "spawn"), timeout: timeout)
    }
}
