import Darwin
import Dispatch
import Foundation

final class SocketPathMonitor: @unchecked Sendable {
    private let path: String
    private let identity: SocketPathIdentity
    private let directoryDescriptor: CInt
    private let source: DispatchSourceFileSystemObject
    private let lock = NSLock()
    private var started = false

    init(path: String) throws {
        self.path = path
        identity = try Self.identity(at: path)
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent().path
        directoryDescriptor = open(directory, O_EVTONLY)
        guard directoryDescriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .ENOENT)
        }
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: directoryDescriptor,
            eventMask: [.write, .delete, .rename],
            queue: DispatchQueue(label: "ghosttykit.socket-path-monitor")
        )
        source.setCancelHandler { [directoryDescriptor] in
            close(directoryDescriptor)
        }
    }

    func waitUntilChanged() async {
        await withTaskCancellationHandler {
            await AsyncStream<Void> { continuation in
                source.setEventHandler { [weak self] in
                    guard let self, pathChanged() else { return }
                    continuation.yield(())
                    continuation.finish()
                    cancel()
                }
                continuation.onTermination = { [weak self] _ in
                    self?.cancel()
                }
                if pathChanged() {
                    continuation.yield(())
                    continuation.finish()
                    resumeOnce()
                    cancel()
                    return
                }
                resumeOnce()
            }.first { _ in true }
        } onCancel: {
            cancel()
        }
    }

    func cancel() {
        source.cancel()
    }

    private func pathChanged() -> Bool {
        (try? Self.identity(at: path)) != identity
    }

    private static func identity(at path: String) throws -> SocketPathIdentity {
        var info = stat()
        if stat(path, &info) != 0 {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .ENOENT)
        }
        return SocketPathIdentity(device: info.st_dev, inode: info.st_ino)
    }

    private func resumeOnce() {
        lock.withLock {
            guard !started else { return }
            started = true
            source.resume()
        }
    }
}

private struct SocketPathIdentity: Equatable {
    let device: dev_t
    let inode: ino_t
}
