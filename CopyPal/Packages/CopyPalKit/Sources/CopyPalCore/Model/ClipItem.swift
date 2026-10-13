import Foundation

/// A history entry as the app sees it: metadata plus the decrypted preview. The
/// pasteboard representations are loaded only when the entry is pasted.
public struct ClipItem: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var createdAt: Date
    /// Copied or pasted most recently; the history is sorted by it.
    public var lastUsedAt: Date
    public var kind: ClipKind
    public var preview: ClipPreview
    public var sourceBundleID: String?
    public var origin: ClipOrigin
    public var sensitivity: Sensitivity?
    public var expiresAt: Date?
    /// Never leaves this Mac (Universal Clipboard, later sync).
    public var localOnly: Bool
    public var pinnedAt: Date?
    public var pinLabel: String?
    public var pinSort: Double?
    public var byteSize: Int
    public var useCount: Int

    public init(
        id: UUID = UUID(),
        createdAt: Date,
        lastUsedAt: Date? = nil,
        kind: ClipKind,
        preview: ClipPreview,
        sourceBundleID: String? = nil,
        origin: ClipOrigin = .local,
        sensitivity: Sensitivity? = nil,
        expiresAt: Date? = nil,
        localOnly: Bool = false,
        pinnedAt: Date? = nil,
        pinLabel: String? = nil,
        pinSort: Double? = nil,
        byteSize: Int = 0,
        useCount: Int = 0
    ) {
        self.id = id
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt ?? createdAt
        self.kind = kind
        self.preview = preview
        self.sourceBundleID = sourceBundleID
        self.origin = origin
        self.sensitivity = sensitivity
        self.expiresAt = expiresAt
        self.localOnly = localOnly
        self.pinnedAt = pinnedAt
        self.pinLabel = pinLabel
        self.pinSort = pinSort
        self.byteSize = byteSize
        self.useCount = useCount
    }

    public var isPinned: Bool {
        pinnedAt != nil
    }

    public var isSensitive: Bool {
        sensitivity != nil
    }

    /// Text shown in lists: the masked form for sensitive entries.
    public var displayTitle: String {
        if let masked = preview.masked { return masked }
        return preview.title
    }
}
