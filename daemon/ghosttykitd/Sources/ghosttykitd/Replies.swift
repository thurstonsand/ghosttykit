import Foundation

struct BridgeCreateReply: Codable {
    let version: Int
    let code: String
    let socketPath: String?
    let leaseToken: String?
    let error: String?

    static func ok(socketPath: String, leaseToken: String) -> BridgeCreateReply {
        BridgeCreateReply(
            version: ProtocolVersion.current,
            code: ProtocolCode.ok,
            socketPath: socketPath,
            leaseToken: leaseToken,
            error: nil
        )
    }
}

struct FrameReply: Codable {
    let version: Int
    let code: String
    let value: String?
    let error: String?

    static func ok(_ value: String? = nil) -> FrameReply {
        FrameReply(
            version: ProtocolVersion.current, code: ProtocolCode.ok, value: value, error: nil
        )
    }

    static func failure(code: String, _ error: String) -> FrameReply {
        FrameReply(version: ProtocolVersion.current, code: code, value: nil, error: error)
    }
}

struct PasteStreamFrameHeader: Encodable {
    let version: Int
    let code: String
    let error: String?
    let kind: String?
    let files: [PasteFrameFile]?
    let bytes: Int?

    static func text(byteCount: Int) -> PasteStreamFrameHeader {
        PasteStreamFrameHeader(
            version: ProtocolVersion.current,
            code: ProtocolCode.ok,
            error: nil,
            kind: "text",
            files: nil,
            bytes: byteCount
        )
    }

    static func files(_ files: [PasteFrameFile]) -> PasteStreamFrameHeader {
        PasteStreamFrameHeader(
            version: ProtocolVersion.current,
            code: ProtocolCode.ok,
            error: nil,
            kind: "files",
            files: files,
            bytes: files.reduce(0) { $0 + $1.bytes }
        )
    }

    static func failure(code: String, _ error: String) -> PasteStreamFrameHeader {
        PasteStreamFrameHeader(
            version: ProtocolVersion.current,
            code: code,
            error: error,
            kind: nil,
            files: nil,
            bytes: nil
        )
    }
}

struct PasteFrameFile: Encodable {
    let fileName: String?
    let mediaType: String?
    let bytes: Int
    let source: String?
}

enum FrameStream {
    case data(Data)
    case file(URL)
}

struct FrameStreamReply {
    let header: any Encodable
    let streams: [FrameStream]
}

func encodeJSONLine(_ value: any Encodable) throws -> Data {
    var data = try JSONEncoder().encode(value)
    data.append(0x0A)
    return data
}
