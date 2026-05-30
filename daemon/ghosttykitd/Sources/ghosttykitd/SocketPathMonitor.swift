import Darwin
import Dispatch
import Foundation

final class SocketPathMonitor: @unchecked Sendable {
    private let path: String
    private let identity: SocketPathIdentity
    private let directoryDescriptor: CInt
    private let eventSource: DispatchSourceFileSystemObject
    private let queue = DispatchQueue(label: "ghosttykit.socket-path-monitor")
    private let lock = NSLock()
    private var sourceStarted = false
    private var state = SocketPathMonitorState.idle

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
        eventSource.setEventHandler { [weak self] in
            self?.finishIfChanged()
        }
        eventSource.setCancelHandler { [directoryDescriptor] in
            close(directoryDescriptor)
        }
    }

    func start() -> Bool {
        let shouldStart = lock.withLock {
            switch state {
            case .idle:
                state = .armed
                return true
            case .armed, .waiting:
                return false
            case .finished:
                return false
            }
        }

        guard shouldStart else { return stateIsActive() }

        resumeOnce()
        finishIfChanged()
        return stateIsActive()
    }

    func waitUntilChanged() async {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                wait(continuation)
            }
        } onCancel: {
            finish()
        }
    }

    func cancel() {
        finish()
    }

    private func wait(_ continuation: CheckedContinuation<Void, Never>) {
        let shouldResume = lock.withLock {
            switch state {
            case .idle:
                preconditionFailure("SocketPathMonitor must be started before waiting")
            case .armed:
                state = .waiting(continuation)
                return false
            case .waiting:
                preconditionFailure("SocketPathMonitor only supports one waiter")
            case .finished:
                return true
            }
        }

        if shouldResume {
            continuation.resume()
        }
    }

    private func stateIsActive() -> Bool {
        lock.withLock {
            switch state {
            case .idle, .armed, .waiting:
                true
            case .finished:
                false
            }
        }
    }

    private func finishIfChanged() {
        guard pathChanged() else { return }
        finish()
    }

    private func finish() {
        let result = lock.withLock {
            switch state {
            case .idle, .armed:
                state = .finished
                return (continuation: nil as CheckedContinuation<Void, Never>?, shouldCancel: true)
            case let .waiting(continuation):
                state = .finished
                return (continuation: continuation, shouldCancel: true)
            case .finished:
                return (continuation: nil as CheckedContinuation<Void, Never>?, shouldCancel: false)
            }
        }

        guard result.shouldCancel else { return }
        resumeOnce()
        eventSource.cancel()
        result.continuation?.resume()
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
            guard !sourceStarted else { return }
            sourceStarted = true
            eventSource.resume()
        }
    }
}

private enum SocketPathMonitorState {
    case idle
    case armed
    case waiting(CheckedContinuation<Void, Never>)
    case finished
}

private struct SocketPathIdentity: Equatable {
    let device: dev_t
    let inode: ino_t
}
