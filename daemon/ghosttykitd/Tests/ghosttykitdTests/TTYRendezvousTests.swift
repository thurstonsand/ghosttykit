import Foundation
import XCTest
@testable import ghosttykitd

final class TTYRendezvousTests: XCTestCase {
    func testRejectsRegularFileWithoutWritingToIt() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghosttykit-tty-\(UUID().uuidString)")
        let original = Data("leave this alone".utf8)
        try original.write(to: path)
        defer { try? FileManager.default.removeItem(at: path) }

        XCTAssertThrowsError(try TTYDevice(path: path.path))
        XCTAssertEqual(try Data(contentsOf: path), original)
    }
}
