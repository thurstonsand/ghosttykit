import Foundation
@testable import ghosttykitd
import XCTest

final class SocketPathMonitorTests: XCTestCase {
    func testSignalsWhenPathIsRemoved() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghosttykit-monitor-\(UUID().uuidString)")
            .path
        FileManager.default.createFile(atPath: path, contents: Data())
        defer { try? FileManager.default.removeItem(atPath: path) }

        let monitor = try SocketPathMonitor(path: path)
        let waiterStarted = expectation(description: "monitor waiter started")
        let changed = expectation(description: "socket path changed")
        Task.detached {
            waiterStarted.fulfill()
            await monitor.waitUntilChanged()
            changed.fulfill()
        }
        wait(for: [waiterStarted], timeout: 1)

        try FileManager.default.removeItem(atPath: path)
        wait(for: [changed], timeout: 2)
    }
}
