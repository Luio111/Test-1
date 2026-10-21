import Foundation

/// Result of looking at a copy: what it is, how it is previewed, and the canonical
/// bytes duplicate detection works on.
public struct Classification: Sendable, Equatable {
    public var kind: ClipKind
    public var preview: ClipPreview
    /// Same content → same bytes, regardless of formatting (HMAC input, see Storage).
    public var fingerprintSource: Data
    /// The text sensitive-content detection runs on; nil for images and files.
    public var text: String?
}

public enum ContentClassifier {
    public static let searchTextLimit = 4_000

    /// Files win over text (Finder adds the file name as text), text wins over images
    /// (spreadsheets add a picture of the cells), an image alone is an image.
    public static func classify(_ content: CapturedContent) -> Classification? {
        let fileURLs = content.fileURLs.filter(\.isFileURL)
        if !fileURLs.isEmpty {
            return files(fileURLs)
        }
        if let text = content.plainText ?? urlText(content), !text.isEmpty {
            return textual(text, content: content)
        }
        if let png = content.data(for: PasteboardTypeID.png) {
            return image(png, capturedFrom: content.hints.capturedFrom)
        }
        if let color = content.hints.color {
            return Classification(
                kind: .color,
                preview: ClipPreview(title: color.hex, characterCount: color.hex.count, color: color, searchText: TextFolding.fold(color.hex)),
                fingerprintSource: Data("color:\(color.hex)".utf8),
                text: nil
            )
        }
        return nil
    }

    private static func urlText(_ content: CapturedContent) -> String? {
        content.data(for: PasteboardTypeID.url).flatMap { String(data: $0, encoding: .utf8) }
    }

    private static func files(_ urls: [URL]) -> Classification {
        let names = urls.map(\.lastPathComponent)
        let title = names.count == 1 ? names[0] : names.joined(separator: ", ")
        return Classification(
            kind: .files,
            preview: ClipPreview(
                title: String(title.prefix(300)),
                lineCount: names.count,
                characterCount: title.count,
                fileNames: names,
                searchText: TextFolding.fold(String(names.joined(separator: " ").prefix(searchTextLimit)))
            ),
            fingerprintSource: Data(("files:" + urls.map(\.absoluteString).joined(separator: "\n")).utf8),
            text: nil
        )
    }

    private static func image(_ png: Data, capturedFrom: String?) -> Classification {
        Classification(
            kind: .image,
            preview: ClipPreview(
                title: "",
                lineCount: 1,
                characterCount: 0,
                imageSize: PNGInfo.size(of: png),
                // The window title makes a screenshot findable (its pixels are not text).
                searchText: TextFolding.fold(String((capturedFrom ?? "").prefix(searchTextLimit))),
                capturedFrom: capturedFrom
            ),
            fingerprintSource: Data("image:".utf8) + png,
            text: nil
        )
    }

    private static func textual(_ text: String, content: CapturedContent) -> Classification {
        let isFormatted = content.contains(PasteboardTypeID.rtf) || content.contains(PasteboardTypeID.html)
        let color = content.hints.color ?? ColorParser.parse(text)
        let link = color == nil ? LinkParser.parse(text) : nil
        let kind: ClipKind = if color != nil {
            .color
        } else if link != nil {
            .link
        } else if isFormatted {
            .richText
        } else {
            .text
        }
        let preview = ClipPreview(
            title: TextFolding.firstLine(of: text),
            lineCount: TextFolding.lineCount(of: text),
            characterCount: text.count,
            link: link,
            color: color,
            isFormatted: isFormatted,
            searchText: TextFolding.fold(String(text.prefix(searchTextLimit)))
        )
        // Plain text only: copying the same text with other formatting is the same entry.
        return Classification(kind: kind, preview: preview, fingerprintSource: Data(("text:" + text).utf8), text: text)
    }
}

public enum PNGInfo {
    private static let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    /// Width and height from the IHDR chunk, without decoding the image.
    public static func size(of data: Data) -> PixelSize? {
        let bytes = [UInt8](data.prefix(24))
        guard bytes.count == 24, Array(bytes[0..<8]) == signature, bytes[12...15] == [0x49, 0x48, 0x44, 0x52] else {
            return nil
        }
        func uint32(at offset: Int) -> Int {
            bytes[offset..<offset + 4].reduce(0) { $0 << 8 | Int($1) }
        }
        return PixelSize(width: uint32(at: 16), height: uint32(at: 20))
    }
}
