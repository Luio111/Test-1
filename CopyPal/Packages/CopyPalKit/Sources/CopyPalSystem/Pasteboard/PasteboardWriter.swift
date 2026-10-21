#if os(macOS)
import AppKit
import CopyPalCore

/// Puts a history entry back on the pasteboard.
public enum PasteboardWriter {
    public struct Options: Sendable, Equatable {
        /// Only the plain text (⇧ in the popup).
        public var plainTextOnly: Bool
        /// `.currentHostOnly`: not offered to the iPhone via Universal Clipboard.
        public var localOnly: Bool
        /// Adds `org.nspasteboard.ConcealedType` so other clipboard managers skip it.
        public var concealed: Bool

        public init(plainTextOnly: Bool = false, localOnly: Bool = false, concealed: Bool = false) {
            self.plainTextOnly = plainTextOnly
            self.localOnly = localOnly
            self.concealed = concealed
        }
    }

    /// Writes the representations (one pasteboard item per stored item index) and
    /// returns the new change count, so the monitor can recognize its own write.
    @discardableResult
    public static func write(_ representations: [ClipRepresentation], to pasteboard: NSPasteboard = .general, options: Options = Options()) -> Int {
        var selected = representations
        if options.plainTextOnly {
            let plain = representations.filter { $0.type == PasteboardTypeID.plainText }
            if !plain.isEmpty { selected = plain }
        }
        let groups = Dictionary(grouping: selected, by: \.item).sorted { $0.key < $1.key }

        pasteboard.prepareForNewContents(with: options.localOnly ? .currentHostOnly : [])
        var items: [NSPasteboardItem] = []
        for (position, group) in groups.enumerated() {
            let item = NSPasteboardItem()
            for representation in group.value {
                item.setData(representation.data, forType: NSPasteboard.PasteboardType(representation.type))
            }
            if position == 0 {
                if let bundleID = Bundle.main.bundleIdentifier {
                    item.setString(bundleID, forType: NSPasteboard.PasteboardType(PasteboardTypeID.source))
                }
                if options.concealed {
                    item.setData(Data(), forType: NSPasteboard.PasteboardType(PasteboardTypeID.concealed))
                }
            }
            items.append(item)
        }
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
        return pasteboard.changeCount
    }
}
#endif
