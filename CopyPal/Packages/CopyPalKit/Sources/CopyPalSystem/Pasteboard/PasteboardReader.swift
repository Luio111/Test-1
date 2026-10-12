#if os(macOS)
import AppKit
import CopyPalCore

/// Reads the pasteboard in two steps (ROADMAP §1.3): first only the type identifiers
/// (decides whether to read at all, never touches content), then the content on a
/// background queue with a size budget and a timeout.
public enum PasteboardReader {
    public struct Budget: Sendable, Equatable {
        public var maxTextBytes: Int
        public var maxImageBytes: Int
        /// At most this many items (files) are read.
        public var maxItems: Int

        public init(maxTextBytes: Int, maxImageBytes: Int, maxItems: Int = 200) {
            self.maxTextBytes = maxTextBytes
            self.maxImageBytes = maxImageBytes
            self.maxItems = maxItems
        }

        public init(_ policy: RetentionPolicy) {
            self.init(maxTextBytes: policy.maxTextBytes, maxImageBytes: policy.maxImageBytes)
        }
    }

    public enum Result: Sendable, Equatable {
        case content(CapturedContent, milliseconds: Double)
        case skipped(CaptureSkipReason)
    }

    /// Type identifiers of all items, in order, without duplicates. Metadata only.
    public static func types(of pasteboard: NSPasteboard) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for item in pasteboard.pasteboardItems ?? [] {
            for type in item.types where seen.insert(type.rawValue).inserted {
                result.append(type.rawValue)
            }
        }
        if result.isEmpty {
            result = pasteboard.types?.map(\.rawValue) ?? []
        }
        return result
    }

    /// `org.nspasteboard.source`, if the writing app set it.
    public static func declaredSource(of pasteboard: NSPasteboard) -> String? {
        pasteboard.string(forType: NSPasteboard.PasteboardType(PasteboardTypeID.source))
    }

    private static let queue = DispatchQueue(label: "CopyPal.PasteboardReader", qos: .utility)

    /// Reads the content of change `expectedChangeCount` off the main thread. Gives up
    /// after `timeout` (an app may be slow to provide promised data) and when the
    /// pasteboard changes during the read.
    public static func read(
        pasteboardName: String,
        expectedChangeCount: Int,
        budget: Budget,
        timeout: TimeInterval = 2
    ) async -> Result {
        await withCheckedContinuation { (continuation: CheckedContinuation<Result, Never>) in
            let gate = ResumeOnce(continuation)
            queue.async {
                let pasteboard = NSPasteboard(name: NSPasteboard.Name(pasteboardName))
                gate.resume(with: readNow(pasteboard, expectedChangeCount: expectedChangeCount, budget: budget))
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                gate.resume(with: .skipped(.timedOut))
            }
        }
    }

    /// Synchronous read on the calling thread.
    public static func readNow(_ pasteboard: NSPasteboard, expectedChangeCount: Int, budget: Budget) -> Result {
        guard pasteboard.changeCount == expectedChangeCount else { return .skipped(.changedWhileReading) }
        let start = DispatchTime.now().uptimeNanoseconds
        var representations: [ClipRepresentation] = []
        var hints = ContentHints()

        let items = pasteboard.pasteboardItems ?? []
        for (index, item) in items.prefix(budget.maxItems).enumerated() {
            let types = Set(item.types.map(\.rawValue))
            // Several items only make sense for files; otherwise the first item is the copy.
            if index > 0, !types.contains(PasteboardTypeID.fileURL) { continue }

            if types.contains(PasteboardTypeID.fileURL), let url = item.string(forType: .fileURL) {
                representations.append(ClipRepresentation(item: index, type: PasteboardTypeID.fileURL, data: Data(url.utf8)))
            }
            if let text = item.string(forType: .string) {
                let data = Data(text.utf8)
                // Too long to keep: the whole copy is skipped (formats alone are no use).
                if data.count > budget.maxTextBytes, index == 0, !types.contains(PasteboardTypeID.fileURL) {
                    return .skipped(.tooLarge)
                }
                if data.count <= budget.maxTextBytes {
                    representations.append(ClipRepresentation(item: index, type: PasteboardTypeID.plainText, data: data))
                }
            }
            guard index == 0 else { continue }

            for type in [PasteboardTypeID.rtf, PasteboardTypeID.html] where types.contains(type) {
                if let data = item.data(forType: NSPasteboard.PasteboardType(type)), data.count <= budget.maxTextBytes {
                    representations.append(ClipRepresentation(type: type, data: data))
                }
            }
            if types.contains(PasteboardTypeID.url), let url = item.string(forType: .URL) {
                representations.append(ClipRepresentation(type: PasteboardTypeID.url, data: Data(url.utf8)))
            }
            if let png = image(from: item, types: types) {
                if png.count > budget.maxImageBytes, representations.isEmpty {
                    return .skipped(.tooLarge)
                }
                if png.count <= budget.maxImageBytes {
                    representations.append(ClipRepresentation(type: PasteboardTypeID.png, data: png))
                }
            }
            if types.contains(PasteboardTypeID.color), let data = item.data(forType: .color) {
                representations.append(ClipRepresentation(type: PasteboardTypeID.color, data: data))
                hints.color = color(from: item)
            }
        }

        guard pasteboard.changeCount == expectedChangeCount else { return .skipped(.changedWhileReading) }
        guard !representations.isEmpty else { return .skipped(.unsupported) }
        let milliseconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        return .content(CapturedContent(representations: representations, hints: hints), milliseconds: milliseconds)
    }

    /// PNG as is; TIFF (e.g. from Preview or older apps) converted to PNG.
    private static func image(from item: NSPasteboardItem, types: Set<String>) -> Data? {
        if types.contains(PasteboardTypeID.png), let png = item.data(forType: .png) {
            return png
        }
        if types.contains(PasteboardTypeID.tiff), let tiff = item.data(forType: .tiff) {
            return ImageConversion.png(fromImageData: tiff)
        }
        return nil
    }

    private static func color(from item: NSPasteboardItem) -> ColorValue? {
        guard let plist = item.propertyList(forType: .color),
              let color = NSColor(pasteboardPropertyList: plist, ofType: .color)?.usingColorSpace(.sRGB) else {
            return nil
        }
        return ColorValue(
            red: Double(color.redComponent),
            green: Double(color.greenComponent),
            blue: Double(color.blueComponent),
            alpha: Double(color.alphaComponent)
        )
    }
}

/// Resumes a continuation exactly once (whichever of read and timeout comes first).
final class ResumeOnce<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Never>?

    init(_ continuation: CheckedContinuation<Value, Never>) {
        self.continuation = continuation
    }

    func resume(with value: Value) {
        let pending: CheckedContinuation<Value, Never>? = lock.withLock {
            defer { continuation = nil }
            return continuation
        }
        pending?.resume(returning: value)
    }
}
#endif
