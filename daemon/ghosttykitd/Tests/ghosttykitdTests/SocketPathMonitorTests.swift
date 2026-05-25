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
        let changed = expectation(description: "socket path changed")
        Task {
            await monitor.waitUntilChanged()
            changed.fulfill()
        }

        try FileManager.default.removeItem(atPath: path)
        wait(for: [changed], timeout: 2)
    }
}
