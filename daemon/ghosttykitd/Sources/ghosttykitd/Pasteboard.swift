import AppKit
import Foundation
import UniformTypeIdentifiers

func readPasteboardContent() throws -> FrameStreamReply {
    let pasteboard = NSPasteboard.general

    let fileItems = try readFileURLItems(from: pasteboard)
    if !fileItems.isEmpty {
        return pasteFrameStreamReply(fileItems)
    }

    if let imageItem = readImageItem(from: pasteboard) {
        return pasteFrameStreamReply([imageItem])
    }

    if let dataItem = readTypedDataItem(from: pasteboard) {
        return pasteFrameStreamReply([dataItem])
    }

    if let text = pasteboard.string(forType: .string), !text.isEmpty {
        let data = Data(text.utf8)
        return FrameStreamReply(header: PasteFrameReply.text(byteCount: data.count), streams: [.data(data)])
    }

    if let dataItem = readFallbackDataItem(from: pasteboard) {
        return pasteFrameStreamReply([dataItem])
    }

    throw PasteboardError.empty
}

enum PasteboardError: Error, LocalizedError {
    case empty

    var errorDescription: String? {
        switch self {
        case .empty: "clipboard has no supported content"
        }
    }

    var protocolCode: String {
        ProtocolCode.pasteEmpty
    }
}

private struct PasteboardFileItem {
    let response: PasteFrameFile
    let stream: FrameStream
}

private func pasteFrameStreamReply(_ items: [PasteboardFileItem]) -> FrameStreamReply {
    FrameStreamReply(header: PasteFrameReply.files(items.map(\.response)), streams: items.map(\.stream))
}

private func readFileURLItems(from pasteboard: NSPasteboard) throws -> [PasteboardFileItem] {
    let objects = pasteboard.readObjects(
        forClasses: [NSURL.self],
        options: [.urlReadingFileURLsOnly: true]
    ) ?? []
    let urls = objects.compactMap { object -> URL? in
        if let url = object as? URL { return url }
        if let url = object as? NSURL { return url as URL }
        return nil
    }

    return try urls.filter { !$0.hasDirectoryPath }.map { url in
        let bytes = try fileSize(url)
        return PasteboardFileItem(
            response: PasteFrameFile(
                fileName: url.lastPathComponent,
                mediaType: mediaType(forFileExtension: url.pathExtension),
                bytes: bytes,
                source: "pasteboard-file"
            ),
            stream: .file(url)
        )
    }
}

private func readImageItem(from pasteboard: NSPasteboard) -> PasteboardFileItem? {
    let data: Data
    if let pngData = pasteboard.data(forType: .png), !pngData.isEmpty {
        data = pngData
    } else if let tiffData = pasteboard.data(forType: .tiff), !tiffData.isEmpty,
              let converted = pngData(fromImageData: tiffData) {
        data = converted
    } else if let image = NSImage(pasteboard: pasteboard), let converted = pngData(from: image) {
        data = converted
    } else {
        return nil
    }

    return PasteboardFileItem(
        response: PasteFrameFile(
            fileName: "clipboard.png",
            mediaType: "image/png",
            bytes: data.count,
            source: "pasteboard-image"
        ),
        stream: .data(data)
    )
}

private struct PasteboardDataCandidate {
    let type: NSPasteboard.PasteboardType
    let fileName: String
    let mediaType: String
}

private func readTypedDataItem(from pasteboard: NSPasteboard) -> PasteboardFileItem? {
    for candidate in knownDataCandidates {
        if let item = readDataItem(from: pasteboard, candidate: candidate, source: "pasteboard-data") {
            return item
        }
    }
    return nil
}

private func readFallbackDataItem(from pasteboard: NSPasteboard) -> PasteboardFileItem? {
    let knownTypes = Set(knownDataCandidates.map(\.type) + [.fileURL, .png, .tiff, .string])
    let fallbackCandidates = (pasteboard.types ?? [])
        .filter { !knownTypes.contains($0) }
        .map(fallbackCandidate)

    let candidatesWithExtension = fallbackCandidates.filter { $0.fileName.contains(".") }
    let candidatesWithoutExtension = fallbackCandidates.filter { !$0.fileName.contains(".") }

    for candidate in candidatesWithExtension + candidatesWithoutExtension {
        if let item = readDataItem(from: pasteboard, candidate: candidate, source: "pasteboard-fallback") {
            return item
        }
    }
    return nil
}

private func readDataItem(
    from pasteboard: NSPasteboard,
    candidate: PasteboardDataCandidate,
    source: String
) -> PasteboardFileItem? {
    guard let data = pasteboard.data(forType: candidate.type), !data.isEmpty else { return nil }
    return PasteboardFileItem(
        response: PasteFrameFile(
            fileName: candidate.fileName,
            mediaType: candidate.mediaType,
            bytes: data.count,
            source: source
        ),
        stream: .data(data)
    )
}

private let knownDataCandidates = [
    PasteboardDataCandidate(type: .pdf, fileName: "pasted-file.pdf", mediaType: "application/pdf"),
    PasteboardDataCandidate(type: .rtf, fileName: "pasted-file.rtf", mediaType: "application/rtf"),
    PasteboardDataCandidate(type: .html, fileName: "pasted-file.html", mediaType: "text/html")
]

private func fallbackCandidate(for type: NSPasteboard.PasteboardType) -> PasteboardDataCandidate {
    let contentType = UTType(type.rawValue)
    let fileName = if let ext = contentType?.preferredFilenameExtension, !ext.isEmpty {
        "pasted-file.\(ext)"
    } else {
        "pasted-file"
    }
    return PasteboardDataCandidate(
        type: type,
        fileName: fileName,
        mediaType: contentType?.preferredMIMEType ?? "application/octet-stream"
    )
}

private func fileSize(_ url: URL) throws -> Int {
    let values = try url.resourceValues(forKeys: [.fileSizeKey])
    if let size = values.fileSize { return size }
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return attributes[.size] as? Int ?? 0
}

private func pngData(from image: NSImage) -> Data? {
    guard let tiffData = image.tiffRepresentation else { return nil }
    return pngData(fromImageData: tiffData)
}

private func pngData(fromImageData data: Data) -> Data? {
    guard let bitmap = NSBitmapImageRep(data: data) else { return nil }
    return bitmap.representation(using: .png, properties: [:])
}

private func mediaType(forFileExtension fileExtension: String) -> String {
    let trimmed = fileExtension.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "application/octet-stream" }
    return UTType(filenameExtension: trimmed)?.preferredMIMEType ?? "application/octet-stream"
}
