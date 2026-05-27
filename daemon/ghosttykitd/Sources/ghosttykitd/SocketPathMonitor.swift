import Darwin
import Dispatch
import Foundation

final class SocketPathMonitor: @unchecked Sendable {
    private let path: String
    private let identity: SocketPathIdentity
    private let directoryDescriptor: CInt
    private let eventSource: DispatchSourceFileSystemObject
    private let timerSource: DispatchSourceTimer
    private let queue = DispatchQueue(label: "ghosttykit.socket-path-monitor")
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
        eventSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: directoryDescriptor,
            eventMask: [.write, .delete, .rename],
            queue: queue
        )
        timerSource = DispatchSource.makeTimerSource(queue: queue)
        timerSource.schedule(deadline: .now() + .milliseconds(100), repeating: .milliseconds(100))
        eventSource.setCancelHandler { [directoryDescriptor] in
            close(directoryDescriptor)
        }
    }

    func waitUntilChanged(onReady: (@Sendable () -> Void)? = nil) async {
        await withTaskCancellationHandler {
            await AsyncStream<Void> { continuation in
                let signalIfChanged = { [weak self] in
                    guard let self, pathChanged() else { return }
                    continuation.yield(())
                    continuation.finish()
                    cancel()
                }
                eventSource.setEventHandler(handler: signalIfChanged)
                timerSource.setEventHandler(handler: signalIfChanged)
                continuation.onTermination = { [weak self] _ in
                    self?.cancel()
                }
                resumeOnce()
                signalIfChanged()
                onReady?()
            }.first { _ in true }
        } onCancel: {
            cancel()
        }
    }

    func cancel() {
        eventSource.cancel()
        timerSource.cancel()
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
            eventSource.resume()
            timerSource.resume()
        }
    }
}

private struct SocketPathIdentity: Equatable {
    let device: dev_t
    let inode: ino_t
}
