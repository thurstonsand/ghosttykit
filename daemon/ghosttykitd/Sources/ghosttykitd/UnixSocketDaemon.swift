import Foundation
import NIOCore
import NIOPosix
import OSLog

final class UnixSocketDaemon {
    private let group = MultiThreadedEventLoopGroup.singleton
    private let logger: Logger
    private let socketPath: String
    private let handler: @Sendable (any CommandRequest) -> CommandResult
    private var serverChannel: (any Channel)?

    init(
        socketPath: String,
        logger: Logger,
        handler: @escaping @Sendable (any CommandRequest) -> CommandResult
    ) {
        self.socketPath = socketPath
        self.logger = logger
        self.handler = handler
    }

    func start() async throws {
        let server = try await bind()
        try await run(server)
    }

    func startDetached() throws -> Task<Void, Error> {
        let semaphore = DispatchSemaphore(value: 0)
        let startup = LockedValue<Result<Void, Error>?>(nil)
        let task = Task {
            do {
                let server = try await bind()
                startup.set(.success(()))
                semaphore.signal()
                try await run(server)
            } catch {
                startup.set(.failure(error))
                semaphore.signal()
                throw error
            }
        }
        semaphore.wait()
        if case let .failure(error) = startup.get() {
            throw error
        }
        return task
    }

    func stop() {
        if let channel = serverChannel {
            try? channel.close(mode: .all).wait()
            serverChannel = nil
        }
        try? FileManager.default.removeItem(atPath: socketPath)
    }

    private func bind() async throws -> NIOAsyncChannel<AcceptedConnection, Never> {
        try ensureSocketParentDirectory()
        let server = try await ServerBootstrap(group: group)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.allowRemoteHalfClosure, value: true)
            .bind(unixDomainSocketPath: socketPath, cleanupExistingSocketFile: true) { channel in
                channel.eventLoop.makeCompletedFuture {
                    try channel.pipeline.syncOperations.addHandler(BackPressureHandler())
                    let asyncChannel = try NIOAsyncChannel(
                        wrappingChannelSynchronously: channel,
                        configuration: NIOAsyncChannel.Configuration(
                            isOutboundHalfClosureEnabled: true,
                            inboundType: ByteBuffer.self,
                            outboundType: ByteBuffer.self
                        )
                    )
                    return AcceptedConnection(asyncChannel: asyncChannel)
                }
            }
        serverChannel = server.channel
        logger.ghosttykit("listening socket=\(socketPath)")
        return server
    }

    private func run(_ server: NIOAsyncChannel<AcceptedConnection, Never>) async throws {
        let monitor = try SocketPathMonitor(path: socketPath)
        guard monitor.start() else {
            logger.ghosttykit("socket path removed or replaced socket=\(socketPath); shutting down")
            try? await server.channel.close(mode: .all).get()
            return
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { [logger, socketPath] in
                await monitor.waitUntilChanged()
                logger.ghosttykit("socket path removed or replaced socket=\(socketPath); shutting down")
                try? await server.channel.close(mode: .all).get()
            }
            group.addTask { [handler, logger] in
                try await Self.acceptClients(server, handler: handler, logger: logger)
            }
            try await group.next()
            group.cancelAll()
        }
    }

    private static func acceptClients(
        _ server: NIOAsyncChannel<AcceptedConnection, Never>,
        handler: @escaping @Sendable (any CommandRequest) -> CommandResult,
        logger: Logger
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            try await server.executeThenClose { clients in
                for try await client in clients {
                    group.addTask {
                        do {
                            try await ConnectionHandler(
                                connection: client, logger: logger, handler: handler
                            ).run()
                        } catch {
                            logger.ghosttykit("connection failed error=\(error)")
                        }
                    }
                }
            }
        }
    }

    private func ensureSocketParentDirectory() throws {
        let parent = URL(fileURLWithPath: socketPath).deletingLastPathComponent().path
        try FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true)
        chmod(parent, 0o700)
    }
}

struct AcceptedConnection {
    let asyncChannel: NIOAsyncChannel<ByteBuffer, ByteBuffer>
}

private final class LockedValue<Value>: @unchecked Sendable {
    // Safe to share across tasks because all access to value is serialized by lock.
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func set(_ value: Value) {
        lock.withLock { self.value = value }
    }

    func get() -> Value {
        lock.withLock { value }
    }
}

private struct ConnectionHandler {
    private let connection: AcceptedConnection
    private let logger: Logger
    private let handler: @Sendable (any CommandRequest) -> CommandResult

    init(
        connection: AcceptedConnection,
        logger: Logger,
        handler: @escaping @Sendable (any CommandRequest) -> CommandResult
    ) {
        self.connection = connection
        self.logger = logger
        self.handler = handler
    }

    func run() async throws {
        let asyncChannel = connection.asyncChannel
        try await asyncChannel.executeThenClose { inbound, _ in
            var connection = ProtocolConnection(inbound: inbound, channel: asyncChannel.channel)
            let command: any CommandRequest
            do {
                guard let decodedCommand = try await RequestReader.readCommand(from: &connection.iterator) else {
                    logger.ghosttykit("empty request")
                    try await connection.closeOutput()
                    return
                }
                command = decodedCommand
            } catch {
                logger.ghosttykit(
                    "request failed before process error=\(error.localizedDescription)"
                )
                try await connection.send(.frame(responseForError(error)))
                try await connection.closeOutput()
                return
            }

            switch handler(command) {
            case .none:
                try await connection.closeOutput()
            case let .reply(reply):
                try await connection.send(reply)
                try await connection.closeOutput()
            case let .hold(holdReply):
                try await connection.send(.frame(holdReply.frame))
                do {
                    try await connection.waitForClientCloseRejectingData()
                } catch {
                    logger.ghosttykit("hold connection rejected extra client data error=\(error.localizedDescription)")
                }
                holdReply.hold.release()
            }
        }
    }
}

struct ProtocolConnection {
    var iterator: NIOAsyncChannelInboundStream<ByteBuffer>.AsyncIterator
    private let writer: ReplyWriter

    init(inbound: NIOAsyncChannelInboundStream<ByteBuffer>, channel: any Channel) {
        iterator = inbound.makeAsyncIterator()
        writer = ReplyWriter(channel: channel)
    }

    func send(_ response: ReplyBody) async throws {
        try await writer.send(response)
    }

    func closeOutput() async throws {
        try await writer.closeOutput()
    }

    mutating func waitForClientCloseRejectingData() async throws {
        while let chunk = try await iterator.next() {
            if chunk.readableBytes > 0 {
                throw RequestValidationError.invalidRequest("client sent data after hold frame")
            }
        }
    }
}

private struct WriteIdleTimeout: Error {}

enum RequestReader {
    private static let maxFrameBytes = 64 * 1024

    static func readCommand(
        from iterator: inout NIOAsyncChannelInboundStream<ByteBuffer>.AsyncIterator
    ) async throws -> (any CommandRequest)? {
        var buffer = Data()
        while var chunk = try await iterator.next() {
            guard let bytes = chunk.readBytes(length: chunk.readableBytes), !bytes.isEmpty else {
                continue
            }
            if let newline = bytes.firstIndex(of: 0x0A) {
                try appendFrameBytes(bytes[..<newline], to: &buffer)
                return try decodeCommand(from: buffer)
            }
            try appendFrameBytes(bytes, to: &buffer)
        }
        guard !buffer.isEmpty else { return nil }
        return try decodeCommand(from: buffer)
    }

    private static func appendFrameBytes(_ bytes: ArraySlice<UInt8>, to buffer: inout Data) throws {
        guard buffer.count + bytes.count <= maxFrameBytes else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: [],
                    debugDescription:
                    "request frame exceeds maximum size of \(maxFrameBytes) bytes"
                )
            )
        }
        buffer.append(contentsOf: bytes)
    }

    private static func appendFrameBytes(_ bytes: [UInt8], to buffer: inout Data) throws {
        try appendFrameBytes(bytes[...], to: &buffer)
    }
}

struct ReplyWriter {
    private static let writeIdleTimeout = Duration.seconds(30)

    private let channel: any Channel

    init(channel: any Channel) {
        self.channel = channel
    }

    func closeOutput() async throws {
        try await withWriteIdleTimeout {
            try await channel.close(mode: .output).get()
        }
    }

    func send(_ response: ReplyBody) async throws {
        switch response {
        case let .frame(jsonResponse):
            try await sendJSON(jsonResponse)
        case let .stream(streamResponse):
            try await send(streamResponse)
        }
    }

    private func send(_ response: FrameStreamReply) async throws {
        try await sendJSON(response.header)
        for stream in response.streams {
            try await send(stream)
        }
    }

    private func sendJSON(_ response: any Encodable) async throws {
        let responseData = try encodeJSONLine(response)
        try await sendData(responseData)
    }

    private func send(_ stream: FrameStream) async throws {
        switch stream {
        case let .data(data):
            try await sendData(data)
        case let .file(url):
            try await sendFile(url)
        }
    }

    private func sendData(_ data: Data) async throws {
        let chunkSize = 1024 * 1024
        var offset = data.startIndex
        while offset < data.endIndex {
            let end =
                data.index(offset, offsetBy: chunkSize, limitedBy: data.endIndex) ?? data.endIndex
            var writableBuffer = ByteBufferAllocator().buffer(
                capacity: data.distance(from: offset, to: end)
            )
            writableBuffer.writeBytes(data[offset ..< end])
            let buffer = writableBuffer
            try await withWriteIdleTimeout {
                try await channel.writeAndFlush(buffer).get()
            }
            offset = end
        }
    }

    private func withWriteIdleTimeout(_ operation: @escaping @Sendable () async throws -> Void) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(for: Self.writeIdleTimeout)
                try await channel.close(mode: .all).get()
                throw WriteIdleTimeout()
            }
            _ = try await group.next()
            group.cancelAll()
        }
    }

    private func sendFile(_ url: URL) async throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            try await sendData(chunk)
        }
    }
}
