import Foundation
import NIOCore
import NIOPosix
import OSLog

final class NetworkServer {
    private let group = MultiThreadedEventLoopGroup.singleton
    private let logger: Logger
    private let socketPath: String
    private let handler: @Sendable (any CommandRequest) -> CommandResult

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
                    return AcceptedConnection(channel: channel, asyncChannel: asyncChannel)
                }
            }

        logger.ghosttykit("listening socket=\(socketPath)")
        try await withThrowingTaskGroup(of: Void.self) { group in
            try await server.executeThenClose { clients in
                for try await client in clients {
                    group.addTask { [handler, logger] in
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

private struct AcceptedConnection {
    let channel: Channel
    let asyncChannel: NIOAsyncChannel<ByteBuffer, ByteBuffer>
}

private struct ConnectionHandler {
    private let connection: AcceptedConnection
    private let logger: Logger
    private let requestReader: RequestReader
    private let replyWriter: ReplyWriter
    private let handler: @Sendable (any CommandRequest) -> CommandResult

    init(
        connection: AcceptedConnection,
        logger: Logger,
        handler: @escaping @Sendable (any CommandRequest) -> CommandResult
    ) {
        self.connection = connection
        self.logger = logger
        requestReader = RequestReader()
        replyWriter = ReplyWriter(channel: connection.channel)
        self.handler = handler
    }

    func run() async throws {
        try await connection.asyncChannel.executeThenClose { inbound, _ in
            let command: any CommandRequest
            do {
                guard let decodedCommand = try await requestReader.readCommand(from: inbound) else {
                    logger.ghosttykit("empty request")
                    return
                }
                command = decodedCommand
            } catch {
                logger.ghosttykit(
                    "request failed before process error=\(error.localizedDescription)"
                )
                try await replyWriter.send(.json(responseForError(error)))
                return
            }

            switch handler(command) {
            case .noReply:
                return
            case let .reply(reply):
                try await replyWriter.send(reply)
            }
        }
    }
}

private struct RequestReader {
    private static let maxFrameBytes = 64 * 1024

    func readCommand(from inbound: NIOAsyncChannelInboundStream<ByteBuffer>) async throws -> (
        any CommandRequest
    )? {
        var buffer = Data()
        for try await var chunk in inbound {
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

    private func appendFrameBytes(_ bytes: ArraySlice<UInt8>, to buffer: inout Data) throws {
        guard buffer.count + bytes.count <= Self.maxFrameBytes else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: [],
                    debugDescription:
                    "request frame exceeds maximum size of \(Self.maxFrameBytes) bytes"
                )
            )
        }
        buffer.append(contentsOf: bytes)
    }

    private func appendFrameBytes(_ bytes: [UInt8], to buffer: inout Data) throws {
        try appendFrameBytes(bytes[...], to: &buffer)
    }
}

private struct ReplyWriter {
    private let channel: Channel

    init(channel: Channel) {
        self.channel = channel
    }

    func send(_ response: FrameReplyBody) async throws {
        switch response {
        case let .json(jsonResponse):
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
            var buffer = ByteBufferAllocator().buffer(
                capacity: data.distance(from: offset, to: end)
            )
            buffer.writeBytes(data[offset ..< end])
            try await channel.writeAndFlush(buffer).get()
            offset = end
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
