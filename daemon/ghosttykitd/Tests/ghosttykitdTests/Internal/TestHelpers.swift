import Foundation
@testable import ghosttykitd
import XCTest

final class UnixJSONConnection {
    private let fd: Int32
    private var buffer = Data()

    init(path: String) throws {
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        guard path.utf8.count < MemoryLayout.size(ofValue: addr.sun_path) else {
            throw POSIXError(.ENAMETOOLONG)
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { rawBuffer in
            for (index, byte) in path.utf8.enumerated() {
                rawBuffer[index] = byte
            }
        }

        let result = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                connect(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
    }

    func send(_ value: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: value)
        data.append(0x0A)
        try data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            var written = 0
            while written < data.count {
                let count = Darwin.write(fd, base.advanced(by: written), data.count - written)
                guard count > 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
                written += count
            }
        }
    }

    func readReply<T: Decodable>() throws -> T {
        while !buffer.contains(0x0A) {
            var chunk = [UInt8](repeating: 0, count: 1024)
            let count = Darwin.read(fd, &chunk, chunk.count)
            guard count > 0 else { throw POSIXError(.EPIPE) }
            buffer.append(contentsOf: chunk.prefix(count))
        }
        let newline = buffer.firstIndex(of: 0x0A)!
        let line = buffer[..<newline]
        buffer.removeSubrange(...newline)
        return try JSONDecoder().decode(T.self, from: line)
    }

    func close() throws {
        guard Darwin.close(fd) == 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
    }
}

extension Optional {
    func requireValue(file: StaticString = #filePath, line: UInt = #line) throws -> Wrapped {
        guard let value = self else {
            XCTFail("missing value", file: file, line: line)
            throw NSError(domain: "ghosttykit.tests", code: 1)
        }
        return value
    }
}

extension FrameReply {
    func errorForTest() -> Error? {
        code == ProtocolCode.ok ? nil : NSError(domain: "ghosttykit.protocol", code: 1)
    }
}

extension CommandResult {
    var frameReply: FrameReply? {
        guard case let .reply(.frame(frame)) = self else { return nil }
        return frame as? FrameReply
    }

    var deferredReply: (@Sendable () async -> ReplyBody)? {
        guard case let .deferred(makeReply) = self else { return nil }
        return makeReply
    }
}

extension ReplyBody {
    var frame: FrameReply? {
        guard case let .frame(frame) = self else { return nil }
        return frame as? FrameReply
    }
}
